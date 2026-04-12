import Foundation

// Wraps the LiteRT-LM iOS inference session. The actual SDK types and method
// names are resolved in Phase 2 against github.com/google-ai-edge/LiteRT-LM
// — everything below is the Phase 0 skeleton that AppContainer needs to
// compile against. See plan.md §A1 and §A2.

enum GemmaError: Error, LocalizedError {
    case notLoaded
    case generationFailed(String)
    case thermalCritical

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "The model is not loaded. Download it in Settings."
        case .generationFailed(let msg):
            return "Generation failed: \(msg)"
        case .thermalCritical:
            return "The device is too hot to run inference. Let it cool down."
        }
    }
}

actor GemmaSession {

    private(set) var isLoaded = false
    private(set) var isGenerating = false
    private var config: ModelConfig = ModelConfig()

    init() {}

    func load(modelPath: String, config: ModelConfig) async throws {
        // TODO(phase 2): Construct the LiteRT-LM session against the real SDK.
        self.config = config
        self.isLoaded = false  // flipped to true in Phase 2 once the session is real
    }

    func unload() {
        isLoaded = false
    }

    /// Single-pass streaming generation. Tool calls, if any, are emitted
    /// inline in the token stream via Gemma 4's native function calling
    /// format — the caller inspects the stream with `SkillParser`. See
    /// plan.md §A2.
    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GemmaError.notLoaded)
        }
    }

    // MARK: - Thermal / low-power guards (B11)

    func currentThermalState() -> ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    func isLowPowerMode() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
