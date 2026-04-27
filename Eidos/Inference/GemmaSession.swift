import Foundation
import CoreGraphics
import CoreImage
import MLX
import MLXLLM
import MLXLMCommon
#if canImport(MLXVLM)
import MLXVLM
#endif
import MLXHuggingFace
import HuggingFace
import Tokenizers

enum GemmaError: Error, LocalizedError {
    case notLoaded
    case filesMissing(String)
    case thermalCritical
    case memoryConstrained(availableMB: Int)

    var errorDescription: String? {
        switch self {
        case .notLoaded: "Model not loaded. Download it first."
        case .filesMissing(let path): "Model files missing at \(path)."
        case .thermalCritical: "Device too hot for inference. Let it cool down."
        case .memoryConstrained(let mb):
            "Not enough free memory (\(mb) MB available). Close some apps and try again."
        }
    }
}

actor GemmaSession {

    /// The current `mlx-swift-lm` public `UserInput` / `Chat.Message`
    /// API exposes images and videos, but not raw audio attachments.
    /// Gemma 4's model internals know about audio tokens; the library
    /// surface we compile against today does not yet let Eidos pass a
    /// PCM buffer into them directly.
    nonisolated static var supportsNativeAudioInput: Bool { false }

    private var modelContainer: ModelContainer?
    private var config = ModelConfig()
    private(set) var isLoaded = false

    /// FIFO queue of waiters for the inference lock. Each `generate(...)`
    /// caller appends a continuation; the previous in-flight inference's
    /// completion resumes the next waiter. Without this, two callers
    /// can race past `inflightInference?.value` simultaneously when the
    /// previous task completes — they'd both see "no inflight" and both
    /// start prefills, double-allocating the GPU buffer.
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []
    private var isInferenceBusy = false

    /// Acquires the inference lock. Suspends if another generation is
    /// running. Pair with `releaseInferenceLock()` in a defer block.
    private func acquireInferenceLock() async {
        if !isInferenceBusy {
            isInferenceBusy = true
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            inferenceWaiters.append(cont)
        }
        // When resumed, we own the lock — `isInferenceBusy` was set to
        // true by the releasing caller, who then resumed our continuation.
    }

    /// Releases the inference lock. If anyone is waiting, hands the
    /// lock to them; otherwise marks the lock free.
    private func releaseInferenceLock() {
        if let next = inferenceWaiters.first {
            inferenceWaiters.removeFirst()
            // Lock stays held; transfers to `next`.
            next.resume()
        } else {
            isInferenceBusy = false
        }
    }

    /// Releases all cached MLX Metal buffers. Must be called between
    /// generations on iPhone — without it, a second `container.generate(...)`
    /// call on the same `ModelContainer` fails GPU buffer allocation
    /// during prefill, which on iOS 26.3.1 manifests as a silent
    /// process kill (no `.ips`, no JetsamEvent, no Swift error). The
    /// mlx-swift-lm benchmark helpers call this between every model
    /// op for the same reason. Cheap on Mac, essential on iPhone.
    private func clearMLXCache() {
        #if !targetEnvironment(simulator)
        // Free cached buffers between generations — same fix the
        // mlx-swift-lm BenchmarkHelpers uses. We do NOT also pin a
        // hard `cacheLimit`. v10 capped it at 256 MB hoping to keep
        // a tight working set, but for a 50-500 token chat reply the
        // KV cache plus activations easily exceed that, and once the
        // limit is hit MLX silently fails its next allocation on
        // iPhone Metal — chat dies mid-stream with no Swift error.
        // Briefing didn't trip this only because briefings are short.
        // Leave the cap at MLX's default (system-driven heuristic).
        MLX.Memory.clearCache()
        #endif
    }

    /// Loads the model from the sandbox `Documents/<variant>/` directory.
    /// The downloader is responsible for populating that directory first.
    func load(variant: GemmaVariant, config: ModelConfig = ModelConfig()) async throws {
        self.config = config

        // The iOS Simulator cannot run MLX. The C++ Metal layer crashes
        // during init with `basic_string(const char*) detected nullptr`
        // regardless of device preference (we tried `Device(.cpu)` — the
        // metallib load is unconditional). So on simulator we pretend the
        // model loaded and serve canned responses from `generate(messages:)`
        // below. Every other piece of the app (memory, RAG, UI, voice,
        // notifications) runs normally.
        #if targetEnvironment(simulator)
        print("[Gemma] Simulator build — using mock inference. Real Gemma runs on physical device / Mac.")
        isLoaded = true
        return
        #else
        let directory = try Self.modelDirectory(for: variant)
        let configPath = directory.appendingPathComponent("config.json").path
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw GemmaError.filesMissing(directory.path)
        }
        modelContainer = try await loadModelContainer(
            from: directory,
            using: #huggingFaceTokenizerLoader()
        )
        isLoaded = true
        #endif
    }

    /// Returns `Documents/<variant.localDirectoryName>/`, creating the parent
    /// directory tree if needed. This is the single source of truth for model
    /// file location — shared with `HuggingFaceDownloader`.
    static func modelDirectory(for variant: GemmaVariant) throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent(variant.localDirectoryName)
    }

    func unload() {
        modelContainer = nil
        isLoaded = false
    }

    /// Streams text chunks from Gemma. Real implementation on device,
    /// canned responses on simulator so the UI flow is testable without
    /// a physical iPhone.
    ///
    /// Accepts optional image and audio inputs that will be passed to
    /// Gemma 4's multimodal pipeline. On the current `MLXLLM` path only
    /// the text is used; image / audio are ignored with a metric log
    /// until the `MLXVLM` upgrade lands. Once VLM is wired, this call
    /// site remains stable — only the internals change.
    ///
    /// - Parameters:
    ///   - messages: system / user / assistant turns
    ///   - images: optional `CGImage` inputs (vision)
    ///   - audio: optional 16 kHz mono Int16 PCM buffer
    ///   - reasoning: chain-of-thought prefix toggle
    func generate(
        messages: [[String: String]],
        images: [CGImage] = [],
        audio: Data? = nil,
        reasoning: ReasoningMode = .fast
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Apply reasoning prefix (if any) to the system message so the
        // downstream inference paths don't need to know about reasoning.
        let effectiveMessages: [[String: String]] = {
            guard reasoning == .reasoning else { return messages }
            let prefix = reasoning.systemPrefix
            if let sysIdx = messages.firstIndex(where: { $0["role"] == "system" }) {
                var m = messages
                let existing = m[sysIdx]["content"] ?? ""
                m[sysIdx]["content"] = prefix + existing
                return m
            } else {
                return [["role": "system", "content": prefix]] + messages
            }
        }()

        // Multimodal path: pass `images` / `audio` through `UserInput`.
        // `MLXLMCommon.UserInput` accepts optional `images` and processes
        // them via the VLM processor when the model config declares
        // vision support. Gemma 4 E2B's config does declare it, so the
        // container's `prepare(input:)` does the right thing even
        // though we import `MLXLLM` — the processor dispatches.
        if !images.isEmpty || (audio != nil && Self.supportsNativeAudioInput) {
            EidosLogger.shared.log(
                .info, category: .model, event: "multimodal.request",
                payload: [
                    "images_count": images.count,
                    "audio_bytes": audio?.count ?? 0,
                ]
            )
            return try await generateMultimodal(
                messages: effectiveMessages,
                images: images,
                audio: audio
            )
        }

        if audio != nil {
            EidosLogger.shared.log(
                .warn, category: .model, event: "audio.input.unsupported",
                message: "Native Gemma audio input is not available in the current mlx-swift-lm API surface.",
                failure: .modelAudioFailed
            )
        }

        return try await generateText(messages: effectiveMessages)
    }

    /// Multimodal generation. Builds a `UserInput` containing the
    /// downsampled images attached to the LAST user `Chat.Message`,
    /// then funnels through `runGuardedGeneration(...)` for the same
    /// FIFO inference lock + `Memory.clearCache()` discipline that
    /// `generateText` uses.
    ///
    /// Both paths share `runGuardedGeneration(...)` so a fix or
    /// regression in one is automatically applied to the other —
    /// the v10 bug where text generation had the lock but multimodal
    /// didn't is impossible by construction now.
    private func generateMultimodal(
        messages: [[String: String]],
        images: [CGImage],
        audio: Data?
    ) async throws -> AsyncThrowingStream<String, Error> {
        #if targetEnvironment(simulator)
        guard isLoaded else { throw GemmaError.notLoaded }
        return Self.mockStream(for: messages)
        #else
        if audio != nil, !Self.supportsNativeAudioInput {
            EidosLogger.shared.log(
                .warn, category: .model, event: "audio.input.ignored",
                message: "Audio buffer was supplied to the multimodal path but the current model bridge cannot consume it.",
                failure: .modelAudioFailed
            )
        }

        // Downsample every incoming image — camera captures are ~48 MP,
        // Gemma's visual encoder caps at 1120 visual tokens anyway.
        // Capping the longest edge drops GPU cycles 10-30× with zero
        // quality impact for typical use.
        let downsampled = images.map { VisionCaptureService.downsample($0) }
        EidosLogger.shared.metric(.model, event: "vision.downsample", values: [
            "input": images.first.map { "\($0.width)x\($0.height)" } ?? "",
            "output": downsampled.first.map { "\($0.width)x\($0.height)" } ?? "",
            "count": downsampled.count,
        ])

        // Build the multimodal UserInput via the `chat:` initializer so
        // the model's `MessageGenerator` injects the correct `<image>`
        // placeholder tokens during chat-template application. Without
        // this we'd hit "Gemma4 image token count mismatch" — soft
        // tokens from the vision encoder with no placeholders to merge
        // them into. Images attach to the LAST user message only.
        let imageObjs: [UserInput.Image] = downsampled.map {
            UserInput.Image.ciImage(CIImage(cgImage: $0))
        }
        var chatMessages: [Chat.Message] = []
        for (idx, msg) in messages.enumerated() {
            let role: Chat.Message.Role = switch msg["role"] ?? "" {
            case "system": .system
            case "user": .user
            case "assistant": .assistant
            case "tool": .tool
            default: .user
            }
            let isLastUserMessage = (msg["role"] == "user") &&
                !messages.dropFirst(idx + 1).contains(where: { $0["role"] == "user" })
            let imgs: [UserInput.Image] = isLastUserMessage ? imageObjs : []
            chatMessages.append(Chat.Message(
                role: role,
                content: msg["content"] ?? "",
                images: imgs
            ))
        }
        let userInput = UserInput(chat: chatMessages)

        return try await runGuardedGeneration(
            userInput: userInput,
            kind: "multimodal",
            messageCount: messages.count
        )
        #endif
    }

    /// Text-only generation. Builds a `UserInput` from the message
    /// dicts, then funnels through `runGuardedGeneration(...)` for the
    /// FIFO inference lock + cache discipline shared with the
    /// multimodal path.
    private func generateText(messages: [[String: String]]) async throws -> AsyncThrowingStream<String, Error> {
        #if targetEnvironment(simulator)
        guard isLoaded else { throw GemmaError.notLoaded }
        return Self.mockStream(for: messages)
        #else
        let userInput = UserInput(
            messages: messages.map { $0.mapValues { $0 as any Sendable } }
        )
        return try await runGuardedGeneration(
            userInput: userInput,
            kind: "text",
            messageCount: messages.count
        )
        #endif
    }

    #if !targetEnvironment(simulator)
    /// Single source of truth for the inference critical section.
    ///
    /// Both `generateText` and `generateMultimodal` build their own
    /// `UserInput` (the only thing the two paths actually differ on)
    /// and then funnel through here. Everything that wraps the MLX
    /// stream lives in this one place:
    ///
    ///   1. `acquireInferenceLock()` — FIFO so two prefills can never
    ///      race against the same `ModelContainer`.
    ///   2. `clearMLXCache()` — frees cached Metal buffers from the
    ///      previous generation. Same call mlx-swift-lm's own
    ///      BenchmarkHelpers makes between every model op.
    ///   3. `container.prepare(input:)` + `container.generate(...)` —
    ///      with explicit lock-release on every throw path so a setup
    ///      failure can't strand subsequent callers.
    ///   4. `wrapMLXStream(...)` — wraps MLX's `AsyncStream<Generation>`
    ///      in a consumer-facing `AsyncThrowingStream<String, Error>`
    ///      and ties the lock + cache release to its terminal events
    ///      (success, error, thermal abort, consumer cancellation).
    ///
    /// A fix or regression in any of these is automatically applied to
    /// both call sites. A whole class of bug ("the lock is in
    /// generateText but not generateMultimodal") is impossible by
    /// construction.
    private func runGuardedGeneration(
        userInput: sending UserInput,
        kind: String,
        messageCount: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Pre-flight memory probe. If we're already inside iOS's
        // jetsam danger zone (< 800 MB headroom), abort with a clean
        // Swift error instead of letting the prefill push us past the
        // ceiling and getting SIGKILL'd. Caught and surfaced to the
        // user as an in-chat error bubble.
        let availableMB = DeviceProfile.availableMemoryMB
        if DeviceProfile.isMemoryConstrained {
            EidosLogger.shared.log(.warn, category: .model,
                event: "generate.\(kind).memory-pressure-abort",
                payload: ["available_mb": availableMB],
                failure: .modelGenerate)
            throw GemmaError.memoryConstrained(availableMB: availableMB)
        }

        await acquireInferenceLock()
        EidosLogger.shared.log(.info, category: .model,
            event: "generate.\(kind).lock-acquired",
            payload: ["available_mb": availableMB])

        clearMLXCache()
        EidosLogger.shared.log(.info, category: .model,
            event: "generate.\(kind).cache-cleared")

        EidosLogger.shared.log(.info, category: .model,
            event: "generate.\(kind).entry",
            payload: ["messages": messageCount, "loaded": isLoaded])

        guard let container = modelContainer else {
            releaseInferenceLock()
            EidosLogger.shared.log(.error, category: .model,
                event: "generate.\(kind).no-container",
                failure: .modelGenerate)
            throw GemmaError.notLoaded
        }

        EidosLogger.shared.log(.info, category: .model,
            event: "generate.\(kind).prepare.start")
        let lmInput: LMInput
        do {
            lmInput = try await container.prepare(input: userInput)
        } catch {
            releaseInferenceLock()
            EidosLogger.shared.error(.model,
                event: "generate.\(kind).prepare.error",
                error: error, failure: .modelGenerate)
            throw error
        }
        EidosLogger.shared.log(.info, category: .model,
            event: "generate.\(kind).prepare.done")

        let effectiveMaxTokens = min(config.maxTokens, DeviceProfile.maxGenerationTokens)
        let params = GenerateParameters(
            maxTokens: effectiveMaxTokens,
            temperature: config.temperature,
            topP: config.topP
        )

        EidosLogger.shared.log(.info, category: .model,
            event: "generate.\(kind).stream.start",
            payload: ["max_tokens": effectiveMaxTokens])
        let stream: AsyncStream<Generation>
        do {
            stream = try await container.generate(input: lmInput, parameters: params)
        } catch {
            releaseInferenceLock()
            EidosLogger.shared.error(.model,
                event: "generate.\(kind).stream.setup-error",
                error: error, failure: .modelGenerate)
            throw error
        }

        return wrapMLXStream(stream, kind: kind)
    }

    /// Wraps an MLX `AsyncStream<Generation>` in a consumer-facing
    /// `AsyncThrowingStream<String, Error>` and ties the inference
    /// lock + cache lifecycle to the stream's terminal events.
    ///
    /// One single wrap shape for both text and multimodal — any tweak
    /// (thermal handling, cancellation policy, post-cleanup ordering)
    /// happens in exactly one place.
    private func wrapMLXStream(
        _ stream: AsyncStream<Generation>,
        kind: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                var emittedAny = false
                var releasedLock = false
                let release: @Sendable () async -> Void = { [weak self] in
                    guard let self else { return }
                    await self.clearMLXCache()
                    await self.releaseInferenceLock()
                    EidosLogger.shared.log(.info, category: .model,
                        event: "generate.\(kind).post-cleanup")
                }
                do {
                    for try await generation in stream {
                        if case .chunk(let text) = generation {
                            if !emittedAny {
                                EidosLogger.shared.log(.info, category: .model,
                                    event: "generate.\(kind).stream.first-token",
                                    payload: [
                                        "chunk_chars": text.count,
                                        "available_mb": DeviceProfile.availableMemoryMB,
                                    ])
                            }
                            emittedAny = true
                            continuation.yield(text)
                        }
                        if ProcessInfo.processInfo.thermalState == .critical {
                            EidosLogger.shared.log(.warn, category: .model,
                                event: "generate.\(kind).stream.thermal-abort",
                                failure: .modelThermal)
                            continuation.finish(throwing: GemmaError.thermalCritical)
                            await release()
                            releasedLock = true
                            return
                        }
                    }
                    EidosLogger.shared.log(.info, category: .model,
                        event: "generate.\(kind).stream.done",
                        payload: [
                            "emitted": emittedAny,
                            "available_mb": DeviceProfile.availableMemoryMB,
                        ])
                    continuation.finish()
                } catch is CancellationError {
                    // Normal cancellation (consumer stopped iterating).
                    // Don't tag as error; just log and finish cleanly.
                    EidosLogger.shared.log(.info, category: .model,
                        event: "generate.\(kind).stream.cancelled",
                        payload: ["emitted": emittedAny])
                    continuation.finish()
                } catch {
                    EidosLogger.shared.error(.model,
                        event: "generate.\(kind).stream.error",
                        error: error, failure: .modelGenerate)
                    continuation.finish(throwing: error)
                }
                if !releasedLock {
                    await release()
                }
                _ = self
            }
            continuation.onTermination = { _ in
                // Cancellation — task body hits CancellationError, runs
                // the catch path, then release(). We just need to make
                // sure the iteration stops draining MLX.
                task.cancel()
            }
        }
    }
    #endif

    // MARK: - Simulator mock

    #if targetEnvironment(simulator)

    /// Produces a plausible response for the three prompt shapes Eidos
    /// sends: chat turns, crystallization (needs JSON), and digest (needs
    /// narration). Detects which by sniffing the system prompt.
    nonisolated static func mockStream(for messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        let system = messages.first(where: { $0["role"] == "system" })?["content"] ?? ""
        let user = messages.last(where: { $0["role"] == "user" })?["content"] ?? ""
        let reply = Self.mockReply(system: system, user: user)

        return AsyncThrowingStream { continuation in
            Task.detached {
                // Stream character-by-character so the UI shows tokens flowing.
                for char in reply {
                    continuation.yield(String(char))
                    try? await Task.sleep(nanoseconds: 20_000_000)  // 20 ms / char
                }
                continuation.finish()
            }
        }
    }

    nonisolated private static func mockReply(system: String, user: String) -> String {
        // Crystallizer expects a JSON array.
        if system.contains("memory-crystallizer") {
            return """
            [
              {
                "title": "Simulator test memory",
                "body": "This entry was produced by the simulator mock crystallizer. On a real device, Gemma extracts durable facts from the conversation here.",
                "tags": ["simulator", "mock"],
                "tier": "topic",
                "priority": 4
              }
            ]
            """
        }

        // Digest-style system prompt.
        if system.contains("morning briefing") {
            return "Good morning. (Simulator mock — on a real device, Gemma narrates from your calendar + reminders + memory. Nothing else on your plate right now.)"
        }

        // Generic chat.
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("2 + 2") || trimmed.contains("2+2") {
            return "4. (Simulator mock response — real Gemma runs on-device on iPhone / Mac.)"
        }
        return "I hear you: \"\(trimmed.prefix(120))\". (Simulator mock — real Gemma runs on-device on iPhone / Mac.)"
    }
    #endif
}
