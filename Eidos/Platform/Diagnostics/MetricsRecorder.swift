import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Darwin

/// Per-generation metrics captured while Gemma streams tokens.
///
/// Captured fields:
///   - `ttftMs` — time to first token, in milliseconds
///   - `totalMs` — total wall time for the generation
///   - `tokens` — total tokens produced
///   - `tokensPerSecond` — throughput at finish
///   - `rssMBBefore` / `rssMBPeak` — resident memory before and peak during
///   - `thermalState` — worst thermal state observed during the call
///   - `failed` / `failureReason` — if generation errored
struct GenerationMetrics: Sendable, Codable {
    var ttftMs: Double?
    var totalMs: Double
    var tokens: Int
    var tokensPerSecond: Double
    var rssMBBefore: Double
    var rssMBPeak: Double
    var thermalState: String
    var failed: Bool
    var failureReason: String?
    /// Prompt length in characters (not tokens — cheap to compute).
    var promptChars: Int
    /// Whether image / audio were included.
    var hadImage: Bool
    var hadAudio: Bool
    var reasoningMode: Bool
}

/// Captures metrics for a single Gemma generation.
///
/// Usage:
/// ```
/// let rec = GenerationMetricsRecorder(prompt: prompt, hasImage: false, hasAudio: false, reasoning: false)
/// rec.start()
/// // ...stream tokens, call `rec.firstToken()` once; `rec.token()` per chunk...
/// let m = rec.finish(failure: nil)
/// EidosLogger.shared.metric(.model, event: "generate", values: m.asDict)
/// ```
///
/// Safe to call from any thread; internal counters use atomic updates.
final class GenerationMetricsRecorder: @unchecked Sendable {

    private let promptChars: Int
    private let hasImage: Bool
    private let hasAudio: Bool
    private let reasoning: Bool

    private var startTime: Date?
    private var firstTokenTime: Date?
    private var tokenCount = 0
    private var rssBefore: Double = 0
    private var rssPeak: Double = 0
    private var worstThermal: ProcessInfo.ThermalState = .nominal
    private let lock = NSLock()
    private var peakSamplerActive = false

    init(prompt: String, hasImage: Bool, hasAudio: Bool, reasoning: Bool) {
        self.promptChars = prompt.count
        self.hasImage = hasImage
        self.hasAudio = hasAudio
        self.reasoning = reasoning
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        startTime = Date()
        rssBefore = Self.residentMemoryMB()
        rssPeak = rssBefore
        worstThermal = ProcessInfo.processInfo.thermalState
        peakSamplerActive = true
        samplePeakAsync()
    }

    /// Call exactly once on the first produced token.
    func firstToken() {
        lock.lock(); defer { lock.unlock() }
        if firstTokenTime == nil { firstTokenTime = Date() }
    }

    /// Call once per produced chunk. `characters` is the chunk length; we
    /// approximate tokens by dividing by 4 if Gemma's chunks are character-
    /// streamed — close enough for logging rates.
    func token(characters: Int = 4) {
        lock.lock(); defer { lock.unlock() }
        // Rough token approximation: 1 token ≈ 4 chars. Good enough for
        // throughput graphs; not for billing.
        tokenCount += max(1, characters / 4)
    }

    /// Stops the recorder and returns final metrics.
    func finish(failure: Error? = nil) -> GenerationMetrics {
        lock.lock(); defer { lock.unlock() }
        peakSamplerActive = false
        let end = Date()
        let total = end.timeIntervalSince(startTime ?? end) * 1000
        let ttft = firstTokenTime.flatMap { $0.timeIntervalSince(startTime ?? $0) * 1000 }
        let tps: Double = total > 0 ? (Double(tokenCount) / (total / 1000)) : 0

        return GenerationMetrics(
            ttftMs: ttft,
            totalMs: total,
            tokens: tokenCount,
            tokensPerSecond: tps,
            rssMBBefore: rssBefore,
            rssMBPeak: rssPeak,
            thermalState: thermalLabel(worstThermal),
            failed: failure != nil,
            failureReason: failure?.localizedDescription,
            promptChars: promptChars,
            hadImage: hasImage,
            hadAudio: hasAudio,
            reasoningMode: reasoning
        )
    }

    // MARK: - Peak sampling

    private func samplePeakAsync() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while self?.peakSamplerActive == true {
                let rss = Self.residentMemoryMB()
                let thermal = ProcessInfo.processInfo.thermalState
                self?.lock.lock()
                if rss > (self?.rssPeak ?? 0) { self?.rssPeak = rss }
                if Self.thermalRank(thermal) > Self.thermalRank(self?.worstThermal ?? .nominal) {
                    self?.worstThermal = thermal
                }
                self?.lock.unlock()
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    private func thermalLabel(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static func thermalRank(_ s: ProcessInfo.ThermalState) -> Int {
        switch s {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 0
        }
    }

    // MARK: - Resident memory via mach

    /// Returns process resident set size in megabytes.
    static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }
}

/// Lightweight standalone memory probe for code paths outside a
/// `GenerationMetricsRecorder`. Logs resident memory + thermal state
/// under a named event so we can correlate crashes / OOM kills with
/// the last-known RAM reading.
///
/// Usage:
/// ```
/// MemoryProbe.snapshot(tag: "before-generate")
/// MemoryProbe.snapshot(tag: "after-context-build")
/// ```
enum MemoryProbe {

    /// Logs a `memory.snapshot` metric with current RSS (MB), available
    /// RAM hint (physical memory / active byte count), and thermal
    /// state. Does nothing outside DEBUG builds to keep release runs
    /// quiet.
    static func snapshot(tag: String) {
        #if DEBUG
        let rss = GenerationMetricsRecorder.residentMemoryMB()
        let thermal = ProcessInfo.processInfo.thermalState
        EidosLogger.shared.metric(.model, event: "memory.snapshot", values: [
            "tag": tag,
            "rss_mb": rss,
            "thermal": thermalLabel(thermal),
            "physical_mb": Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024),
        ])
        #endif
    }

    private static func thermalLabel(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

extension GenerationMetrics {
    /// Serialises to a `[String: Any?]` suitable for the logger payload.
    var asDict: [String: Any?] {
        [
            "ttft_ms": ttftMs as Any?,
            "total_ms": totalMs,
            "tokens": tokens,
            "tok_per_sec": tokensPerSecond,
            "rss_mb_before": rssMBBefore,
            "rss_mb_peak": rssMBPeak,
            "thermal": thermalState,
            "failed": failed,
            "failure_reason": failureReason as Any?,
            "prompt_chars": promptChars,
            "had_image": hadImage,
            "had_audio": hadAudio,
            "reasoning": reasoningMode,
        ]
    }
}
