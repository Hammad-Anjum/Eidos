import Foundation
import CoreGraphics
@testable import Eidos

/// Test-only `InferenceSession` that returns canned token streams.
/// Lets the chat regression tests run on simulator without standing
/// up MLX or downloading model weights. Behavior is configured per
/// instance:
///
/// - `cannedReply` — string broken into tokens and yielded one at a
///   time with `tokenIntervalMs` between yields.
/// - `errorAt` — if non-nil, the stream throws after emitting that
///   many tokens. Use to test the chat path's error handling.
/// - `delayFirstTokenMs` — pause before the first token, used to
///   verify timeouts / first-token-latency behavior.
///
/// Counters (`callCount`, `lastMessages`, etc.) let tests assert that
/// the chat path called the session correctly without poking at
/// private state.
final class MockInferenceSession: InferenceSession {

    static var supportsNativeAudioInput: Bool { false }

    var isLoaded: Bool { true }

    // MARK: - Configuration

    var cannedReply: String = "Hello, this is a test response."
    var tokenIntervalMs: Int = 5
    var delayFirstTokenMs: Int = 0
    var errorAt: Int? = nil
    var thrownError: Error = MockError.scripted

    // MARK: - Inspection

    private(set) var callCount: Int = 0
    private(set) var lastMessages: [[String: String]] = []
    private(set) var lastImageCount: Int = 0
    private(set) var lastAudioBytes: Int = 0
    private(set) var lastReasoning: ReasoningMode = .fast

    // MARK: - InferenceSession

    func generate(
        messages: [[String: String]],
        images: [CGImage],
        audio: Data?,
        reasoning: ReasoningMode
    ) async throws -> AsyncThrowingStream<String, Error> {
        callCount += 1
        lastMessages = messages
        lastImageCount = images.count
        lastAudioBytes = audio?.count ?? 0
        lastReasoning = reasoning

        let reply = cannedReply
        let interval = tokenIntervalMs
        let firstDelay = delayFirstTokenMs
        let errorIndex = errorAt
        let err = thrownError

        return AsyncThrowingStream { continuation in
            Task {
                if firstDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(firstDelay) * 1_000_000)
                }
                // Tokenize naively — split by space + emit per token.
                let tokens = reply.split(separator: " ").map(String.init)
                for (idx, token) in tokens.enumerated() {
                    if let errAt = errorIndex, idx >= errAt {
                        continuation.finish(throwing: err)
                        return
                    }
                    continuation.yield(idx == 0 ? token : " " + token)
                    if interval > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }

    enum MockError: Error, LocalizedError {
        case scripted
        var errorDescription: String? { "MockInferenceSession: scripted failure" }
    }
}
