import Foundation
import CoreGraphics

/// Decouples consumers (RAGPipeline, MemoryCrystallizer, DigestGenerator)
/// from the concrete inference backend. Today the only implementation
/// is `GemmaSession` (mlx-swift-lm + Gemma 4 E2B). When a future
/// backend lands — Qwen 2.5 VL via mlx-swift-lm, an Apple Foundation
/// Models adapter, or LiteRT-LM — a new conformance can drop in
/// without touching call sites.
///
/// Designed to mirror the `GemmaSession.generate(...)` signature
/// exactly so retrofitting the existing actor is a one-line
/// "extension GemmaSession: InferenceSession {}".
///
/// Why a protocol vs. a base class:
///   - Backends will be Swift actors of different shapes
///     (LiteRT-LM is C++ behind an actor wrapper, MLX-VLM is an
///     mlx-swift-lm actor). A protocol lets each implementer pick
///     its own internal isolation strategy.
///   - Lets tests inject a fake `InferenceSession` that returns
///     canned token streams without standing up MLX, unblocking
///     the regression test suite (Action: TESTS).
protocol InferenceSession: Sendable {

    /// Whether the underlying model accepts audio buffers directly,
    /// without going through SFSpeechRecognizer first. Currently false
    /// for every conformer because mlx-swift-lm's public UserInput API
    /// doesn't expose an audio-buffer slot — Gemma 4's audio tokens
    /// exist but aren't reachable from Swift.
    static var supportsNativeAudioInput: Bool { get }

    /// Whether the model is loaded into memory and ready to generate.
    /// Implementations should make this a snapshot of internal state,
    /// not block on a load.
    var isLoaded: Bool { get async }

    /// Streams text chunks from the model. The contract:
    ///   - Honors `messages` as the prompt (system / user / assistant).
    ///   - When `images` is non-empty AND the implementation supports
    ///     vision, attaches the images to the last user turn.
    ///   - When `audio` is non-empty AND
    ///     `Self.supportsNativeAudioInput` is true, attaches the audio
    ///     buffer (otherwise audio is ignored with a log line).
    ///   - `reasoning` toggles chain-of-thought prefix: implementers
    ///     can choose to inject extra system instruction.
    ///   - Returns an `AsyncThrowingStream<String, Error>` that yields
    ///     decoded chunks until completion. The stream finishes
    ///     normally on success, throws on error (Swift / model /
    ///     thermal abort), or finishes on cancellation.
    func generate(
        messages: [[String: String]],
        images: [CGImage],
        audio: Data?,
        reasoning: ReasoningMode
    ) async throws -> AsyncThrowingStream<String, Error>
}

// Make the existing actor conform without changing its surface. The
// `generate(messages:images:audio:reasoning:)` method already exists
// with this exact signature.
extension GemmaSession: InferenceSession {}
