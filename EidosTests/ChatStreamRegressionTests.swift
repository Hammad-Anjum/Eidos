import XCTest
@testable import Eidos

/// End-to-end-ish chat regression tests using `MockInferenceSession`.
///
/// These exercise the streaming + cancellation + error contracts of
/// the chat consumer pattern (the same shape `ChatViewModel.send`
/// uses) without needing MLX, the GemmaSession actor lock, or any
/// real model weights. If any of these fail, a chat regression has
/// been introduced and we should catch it here, not in IPA-cycle
/// debugging with the tester.
final class ChatStreamRegressionTests: XCTestCase {

    // MARK: - Streaming reaches consumer

    func test_mockSession_streams_complete_reply_in_order() async throws {
        let mock = MockInferenceSession()
        mock.cannedReply = "alpha bravo charlie delta"
        mock.tokenIntervalMs = 0  // tight loop in tests

        let stream = try await mock.generate(
            messages: [["role": "user", "content": "test"]],
            images: [],
            audio: nil,
            reasoning: .fast
        )

        var collected = ""
        for try await chunk in stream { collected += chunk }
        XCTAssertEqual(collected, "alpha bravo charlie delta")
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_mockSession_records_what_it_was_called_with() async throws {
        let mock = MockInferenceSession()
        mock.cannedReply = "ok"
        mock.tokenIntervalMs = 0

        let messages = [
            ["role": "system", "content": "you are eidos"],
            ["role": "user", "content": "hello"],
        ]
        let stream = try await mock.generate(
            messages: messages, images: [], audio: nil, reasoning: .reasoning
        )
        for try await _ in stream { }   // drain

        XCTAssertEqual(mock.lastMessages.count, 2)
        XCTAssertEqual(mock.lastMessages[0]["role"], "system")
        XCTAssertEqual(mock.lastMessages[1]["content"], "hello")
        XCTAssertEqual(mock.lastReasoning, .reasoning)
    }

    // MARK: - Error propagation

    func test_mockSession_propagates_scripted_error() async throws {
        let mock = MockInferenceSession()
        mock.cannedReply = "one two three four five"
        mock.tokenIntervalMs = 0
        mock.errorAt = 2     // throw after 2 tokens emitted

        let stream = try await mock.generate(
            messages: [["role": "user", "content": "x"]],
            images: [], audio: nil, reasoning: .fast
        )
        var collected = ""
        var caught: Error?
        do {
            for try await chunk in stream { collected += chunk }
        } catch {
            caught = error
        }
        XCTAssertNotNil(caught, "Stream should have thrown after errorAt count.")
        XCTAssertTrue(collected.contains("one"))
        XCTAssertTrue(collected.contains("two"))
        XCTAssertFalse(collected.contains("five"))
    }

    // MARK: - Cancellation

    func test_mockSession_handles_consumer_cancellation_gracefully() async throws {
        let mock = MockInferenceSession()
        mock.cannedReply = String(repeating: "tok ", count: 50)
        mock.tokenIntervalMs = 5    // slow enough to cancel mid-stream

        let stream = try await mock.generate(
            messages: [["role": "user", "content": "x"]],
            images: [], audio: nil, reasoning: .fast
        )

        let consumer = Task {
            var n = 0
            for try await _ in stream {
                n += 1
                if n >= 3 { break }   // simulate "user navigated away"
            }
            return n
        }
        let count = try await consumer.value
        XCTAssertEqual(count, 3, "Consumer should have stopped at the requested count without crashing.")
    }

    // MARK: - First-token latency

    func test_mockSession_respects_first_token_delay() async throws {
        let mock = MockInferenceSession()
        mock.cannedReply = "hi"
        mock.tokenIntervalMs = 0
        mock.delayFirstTokenMs = 50

        let start = Date()
        let stream = try await mock.generate(
            messages: [["role": "user", "content": "x"]],
            images: [], audio: nil, reasoning: .fast
        )
        var firstAt: Date?
        for try await _ in stream where firstAt == nil {
            firstAt = Date()
        }
        XCTAssertNotNil(firstAt)
        let elapsed = (firstAt ?? start).timeIntervalSince(start) * 1000
        XCTAssertGreaterThanOrEqual(elapsed, 40, "First token must arrive after ~50ms delay.")
    }

    // MARK: - InferenceSession protocol shape

    func test_mockSession_conforms_to_protocol() {
        let mock: InferenceSession = MockInferenceSession()
        XCTAssertNotNil(mock)
    }
}
