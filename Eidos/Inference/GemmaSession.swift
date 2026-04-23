import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

enum GemmaError: Error, LocalizedError {
    case notLoaded
    case filesMissing(String)
    case thermalCritical

    var errorDescription: String? {
        switch self {
        case .notLoaded: "Model not loaded. Download it first."
        case .filesMissing(let path): "Model files missing at \(path)."
        case .thermalCritical: "Device too hot for inference. Let it cool down."
        }
    }
}

actor GemmaSession {

    private var modelContainer: ModelContainer?
    private var config = ModelConfig()
    private(set) var isLoaded = false

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
    func generate(messages: [[String: String]]) async throws -> AsyncThrowingStream<String, Error> {
        #if targetEnvironment(simulator)
        guard isLoaded else { throw GemmaError.notLoaded }
        return Self.mockStream(for: messages)
        #else
        guard let container = modelContainer else {
            throw GemmaError.notLoaded
        }

        let userInput = UserInput(
            messages: messages.map { $0.mapValues { $0 as any Sendable } }
        )
        let lmInput = try await container.prepare(input: userInput)
        let params = GenerateParameters(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP
        )

        let stream = try await container.generate(input: lmInput, parameters: params)

        return AsyncThrowingStream { continuation in
            let task = Task {
                for await generation in stream {
                    if case .chunk(let text) = generation {
                        continuation.yield(text)
                    }
                    if ProcessInfo.processInfo.thermalState == .critical {
                        continuation.finish(throwing: GemmaError.thermalCritical)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #endif
    }

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
