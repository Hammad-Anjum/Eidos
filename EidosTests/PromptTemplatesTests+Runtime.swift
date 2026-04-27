import XCTest
@testable import Eidos

/// Tests for the Phase 8 prompt additions:
///   - `runtimeContextBlock(now:)` — must inject the date, time, timezone
///     so Gemma can answer "what day is it" questions. Regression guard
///     for the bug where Gemma invented dates because no block existed.
///   - `chat(...)` — must include the runtime block in the system message
///     in the correct order (identity → runtime → retrieved → tools).
final class PromptTemplatesRuntimeTests: XCTestCase {

    func testRuntimeContextBlockContainsCriticalFields() {
        let now = Date(timeIntervalSince1970: 1_714_060_800) // 2026-04-23 10:40 UTC
        let block = PromptTemplates.runtimeContextBlock(now: now)
        XCTAssertTrue(block.contains("# Runtime context"))
        XCTAssertTrue(block.contains("Current date:"))
        XCTAssertTrue(block.contains("Current time:"))
        XCTAssertTrue(block.contains("Timezone:"))
        XCTAssertTrue(block.contains("ISO week:"))
    }

    func testRuntimeContextBlockIncludesUserNameWhenProvided() {
        let now = Date()
        let block = PromptTemplates.runtimeContextBlock(now: now, userDisplayName: "Hissamuddin")
        XCTAssertTrue(block.contains("Hissamuddin"), "User name should be injected when provided")
    }

    func testRuntimeContextBlockOmitsUserNameWhenNil() {
        let block = PromptTemplates.runtimeContextBlock(now: Date(), userDisplayName: nil)
        XCTAssertFalse(block.contains("User's preferred name"))
    }

    func testChatSystemPromptIncludesRuntimeBlockBeforeRetrievedContext() {
        let messages = PromptTemplates.chat(
            history: [] as [(role: String, content: String)],
            userMessage: "hi",
            retrievedContext: "## What I remember\n- User loves tea"
        )
        let system = messages.first(where: { $0["role"] == "system" })?["content"] ?? ""

        let runtimeIdx = system.range(of: "# Runtime context")?.lowerBound
        let memoryIdx = system.range(of: "## What I remember")?.lowerBound

        XCTAssertNotNil(runtimeIdx)
        XCTAssertNotNil(memoryIdx)
        if let r = runtimeIdx, let m = memoryIdx {
            XCTAssertLessThan(r, m, "Runtime block must precede retrieved context")
        }
    }

    func testChatSystemPromptMentionsUseRuntimeFacts() {
        // Regression guard: the upgraded system prompt must explicitly
        // tell Gemma to USE the runtime block. If this assertion fails,
        // someone shrunk the prompt and date questions will regress.
        let messages = PromptTemplates.chat(history: [] as [(role: String, content: String)], userMessage: "hi")
        let system = messages.first(where: { $0["role"] == "system" })?["content"] ?? ""
        XCTAssertTrue(system.contains("Always use these facts."), "System prompt must instruct the model to use runtime facts")
    }

    func testChatPartOfDayClassification() {
        // Morning (09:00)
        let morning = PromptTemplates.runtimeContextBlock(
            now: Date(timeIntervalSince1970: dateAt(hour: 9))
        )
        XCTAssertTrue(morning.contains("morning"))

        // Evening (19:00)
        let evening = PromptTemplates.runtimeContextBlock(
            now: Date(timeIntervalSince1970: dateAt(hour: 19))
        )
        XCTAssertTrue(evening.contains("evening"))
    }

    // Helper: create a timestamp at the given hour today in the current
    // timezone. `runtimeContextBlock` uses `TimeZone.current`, so the
    // test must do the same to stay deterministic across CI runners.
    private func dateAt(hour: Int) -> TimeInterval {
        var comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day], from: Date()
        )
        comps.hour = hour
        comps.minute = 0
        comps.timeZone = TimeZone.current
        let cal = Calendar(identifier: .gregorian)
        return (cal.date(from: comps) ?? Date()).timeIntervalSince1970
    }
}
