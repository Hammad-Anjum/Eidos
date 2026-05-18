import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Result for one benchmark prompt execution.
struct BenchmarkResult: Sendable, Codable {
    let promptID: String
    let category: BenchmarkCategory
    let score: Double
    let reason: String
    let response: String
    let metrics: GenerationMetrics
    /// Captured at run time so results are attributable to a build.
    let ranAt: Date
    let gemmaVariantRaw: String
    let reasoningMode: String
    /// True when the SafetyGate intercepted before Gemma was invoked.
    let safetyGateCaught: Bool
}

/// Aggregate summary of a benchmark run.
struct BenchmarkSummary: Sendable, Codable {
    let ranAt: Date
    let deviceName: String
    let totalPrompts: Int
    let succeeded: Int
    let averageScore: Double
    let medianTTFTms: Double?
    let medianTokensPerSecond: Double
    let byCategory: [String: CategorySummary]
    let results: [BenchmarkResult]
}

struct CategorySummary: Sendable, Codable {
    let count: Int
    let averageScore: Double
    let averageTokensPerSecond: Double
}

/// Executes the standard benchmark corpus against a `GemmaSession`,
/// records metrics, and writes a report.
///
/// The runner is deliberately *sequential* — MLX generation on-device
/// saturates the GPU, and running prompts in parallel would skew
/// TTFT and tok/s measurements.
@MainActor
@Observable
final class BenchmarkRunner {

    /// Progress from 0...1 during a run. Observable for UI.
    var progress: Double = 0

    /// Currently executing prompt ID, for the UI.
    var currentPromptID: String? = nil

    /// Whether a run is in progress.
    var isRunning: Bool = false

    /// Last completed run's summary. Nil until the first run finishes.
    var lastSummary: BenchmarkSummary? = nil

    private let gemma: GemmaSession
    private let variant: GemmaVariant

    init(gemma: GemmaSession, variant: GemmaVariant) {
        self.gemma = gemma
        self.variant = variant
    }

    /// Runs the corpus.
    ///
    /// - Parameters:
    ///   - subset: if non-empty, only prompts in these categories run.
    ///   - visionAvailable: set to `false` to skip image-requiring
    ///     prompts (until MLXVLM lands)
    ///   - audioAvailable: set to `false` to skip audio-requiring prompts
    ///   - reasoning: force this reasoning mode for every prompt
    @discardableResult
    func run(
        subset: Set<BenchmarkCategory> = [],
        visionAvailable: Bool = false,
        audioAvailable: Bool = false,
        reasoning: ReasoningMode = .fast
    ) async -> BenchmarkSummary {
        isRunning = true
        defer { isRunning = false }

        EidosLogger.shared.log(.info, category: .benchmark, event: "run.start", payload: [
            "reasoning": reasoning.rawValue,
            "vision": visionAvailable,
            "audio": audioAvailable,
            "subset": Array(subset.map { $0.rawValue }),
        ])

        let corpus: [BenchmarkPrompt] = BenchmarkCorpus.all.filter { p in
            if !subset.isEmpty && !subset.contains(p.category) { return false }
            if p.needsImage && !visionAvailable { return false }
            if p.needsAudio && !audioAvailable { return false }
            return true
        }

        var results: [BenchmarkResult] = []
        progress = 0

        for (idx, prompt) in corpus.enumerated() {
            currentPromptID = prompt.id
            let result = await runOne(prompt, reasoning: reasoning)
            results.append(result)
            progress = Double(idx + 1) / Double(corpus.count)
        }
        currentPromptID = nil

        let summary = summarize(results)
        lastSummary = summary
        persist(summary)
        EidosLogger.shared.log(.info, category: .benchmark, event: "run.done", payload: [
            "total": summary.totalPrompts,
            "succeeded": summary.succeeded,
            "avg_score": summary.averageScore,
        ])
        return summary
    }

    // MARK: - Per-prompt

    /// Truncates a response to a safe size for the benchmark report.
    /// Full streams can be 10 KB+; holding 44 of them in memory while
    /// the model is also loaded pushes iPad-class memory hard. 2 KB
    /// per response keeps the whole run under 100 KB while leaving
    /// enough text to score rubrics against.
    private static let maxStoredResponseChars = 2_000

    private func runOne(_ prompt: BenchmarkPrompt, reasoning: ReasoningMode) async -> BenchmarkResult {
        // 1. Safety gate first. If it catches, we record an
        //    immediate result with the gate response.
        let gateDecision = SafetyGate.evaluate(prompt.prompt)
        if case .refuse(_, let response) = gateDecision {
            let rubric = prompt.rubric(response)
            let fakeMetrics = GenerationMetrics(
                ttftMs: 0, totalMs: 0, tokens: 0, tokensPerSecond: 0,
                rssMBBefore: GenerationMetricsRecorder.residentMemoryMB(),
                rssMBPeak: GenerationMetricsRecorder.residentMemoryMB(),
                thermalState: "nominal", failed: false, failureReason: nil,
                promptChars: prompt.prompt.count,
                hadImage: prompt.needsImage, hadAudio: prompt.needsAudio,
                reasoningMode: reasoning == .reasoning
            )
            return BenchmarkResult(
                promptID: prompt.id,
                category: prompt.category,
                score: rubric.score,
                reason: "[safety-gate] " + rubric.reason,
                response: response,
                metrics: fakeMetrics,
                ranAt: Date(),
                gemmaVariantRaw: variant.rawValue,
                reasoningMode: reasoning.rawValue,
                safetyGateCaught: true
            )
        }

        // 2. Build messages.
        var messages: [[String: String]] = []
        if let sys = prompt.systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": prompt.prompt])

        // 3. Run Gemma with metrics.
        let rec = GenerationMetricsRecorder(
            prompt: prompt.prompt,
            hasImage: prompt.needsImage,
            hasAudio: prompt.needsAudio,
            reasoning: reasoning == .reasoning
        )
        rec.start()

        var response = ""
        var thrown: Error? = nil
        let fixtures = mediaFixture(for: prompt)
        do {
            let stream = try await gemma.generate(
                messages: messages,
                images: fixtures.images,
                audio: fixtures.audio,
                reasoning: reasoning
            )
            var seenFirst = false
            for try await chunk in stream {
                if !seenFirst { rec.firstToken(); seenFirst = true }
                rec.token(characters: chunk.count)
                response += chunk
            }
        } catch {
            thrown = error
            EidosLogger.shared.error(.benchmark, event: "benchmark.error", error: error,
                failure: .benchmarkFailed, extra: ["prompt_id": prompt.id])
        }

        let metrics = rec.finish(failure: thrown)
        let rubric = thrown != nil
            ? (score: 0.0, reason: "error: \(thrown!.localizedDescription)")
            : prompt.rubric(response)

        // Truncate the stored response. The rubric already ran against
        // the full text; the stored copy is for human inspection only.
        let storedResponse = response.count > Self.maxStoredResponseChars
            ? String(response.prefix(Self.maxStoredResponseChars)) + "… [truncated]"
            : response

        return BenchmarkResult(
            promptID: prompt.id,
            category: prompt.category,
            score: rubric.score,
            reason: rubric.reason,
            response: storedResponse,
            metrics: metrics,
            ranAt: Date(),
            gemmaVariantRaw: variant.rawValue,
            reasoningMode: reasoning.rawValue,
            safetyGateCaught: false
        )
    }

    private func mediaFixture(for prompt: BenchmarkPrompt) -> (images: [CGImage], audio: Data?) {
        switch prompt.id {
        case "vision.ocr.basic":
            return (BenchmarkFixtures.ocrImage.map { [$0] } ?? [], nil)
        case "vision.scene.basic":
            return (BenchmarkFixtures.sceneImage.map { [$0] } ?? [], nil)
        case "audio.transcribe.basic":
            return ([], BenchmarkFixtures.syntheticPCM)
        // AuADHD vision-tool fixtures: reuse the synthetic scene image
        // so the Day-1 reliability gate exercises the vision path. Any
        // new `auADHD` prompt with `needsImage: true` must be added here
        // — falling through to the default returns no image and the
        // benchmark result is meaningless.
        case "auadhd.scene.tool":
            return (BenchmarkFixtures.sceneImage.map { [$0] } ?? [], nil)
        default:
            return ([], nil)
        }
    }

    // MARK: - Summarise

    private func summarize(_ results: [BenchmarkResult]) -> BenchmarkSummary {
        let total = results.count
        let succeeded = results.filter { $0.score >= 0.6 }.count
        let avg = results.isEmpty ? 0 : results.map { $0.score }.reduce(0, +) / Double(total)
        let ttfts = results.compactMap { $0.metrics.ttftMs }.sorted()
        let medianTTFT: Double? = ttfts.isEmpty ? nil : ttfts[ttfts.count / 2]
        let tps = results.map { $0.metrics.tokensPerSecond }.sorted()
        let medianTPS = tps.isEmpty ? 0 : tps[tps.count / 2]

        var byCat: [String: CategorySummary] = [:]
        for cat in BenchmarkCategory.allCases {
            let inCat = results.filter { $0.category == cat }
            guard !inCat.isEmpty else { continue }
            byCat[cat.rawValue] = CategorySummary(
                count: inCat.count,
                averageScore: inCat.map { $0.score }.reduce(0, +) / Double(inCat.count),
                averageTokensPerSecond: inCat.map { $0.metrics.tokensPerSecond }.reduce(0, +) / Double(inCat.count)
            )
        }

        let deviceName: String = {
            #if targetEnvironment(simulator)
            return "iOS Simulator"
            #elseif os(iOS)
            return "iOS device"
            #else
            return "Mac (Designed for iPad)"
            #endif
        }()

        return BenchmarkSummary(
            ranAt: Date(),
            deviceName: deviceName,
            totalPrompts: total,
            succeeded: succeeded,
            averageScore: avg,
            medianTTFTms: medianTTFT,
            medianTokensPerSecond: medianTPS,
            byCategory: byCat,
            results: results
        )
    }

    // MARK: - Persist

    private func persist(_ summary: BenchmarkSummary) {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true
            )
            let dir = base.appendingPathComponent("eidos/benchmarks", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            let filename = "\(f.string(from: summary.ranAt)).json"
                .replacingOccurrences(of: ":", with: "-")
            let url = dir.appendingPathComponent(filename)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(summary).write(to: url, options: .atomic)
        } catch {
            EidosLogger.shared.error(.benchmark, event: "persist.failed",
                error: error, failure: .loggerWriteFailed)
        }
    }
}

private enum BenchmarkFixtures {

    static let syntheticPCM: Data = {
        let sampleRate = 16_000.0
        let seconds = 1.0
        let count = Int(sampleRate * seconds)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            samples[index] = Int16(Double(Int16.max) * 0.25 * sin(2 * .pi * 440 * t))
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    static var ocrImage: CGImage? {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 420))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 420))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 148, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            let text = NSAttributedString(string: "EIDOS 2026", attributes: attrs)
            text.draw(in: CGRect(x: 110, y: 120, width: 980, height: 180))
        }
        return image.cgImage
        #else
        return nil
        #endif
    }

    static var sceneImage: CGImage? {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 768))
        let image = renderer.image { ctx in
            UIColor(white: 0.98, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 768))

            UIColor.systemRed.setFill()
            ctx.cgContext.fill(CGRect(x: 312, y: 184, width: 400, height: 400))
        }
        return image.cgImage
        #else
        return nil
        #endif
    }
}
