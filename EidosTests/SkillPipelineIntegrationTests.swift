import XCTest
@testable import Eidos

/// End-to-end tests for the "brain fix" pipeline: user turn →
/// `SkillParser` → `SkillRegistry` → skill invocation. Uses a real
/// `SkillRegistry` with a stub skill so no EventKit / HealthKit / MLX
/// is touched during the test run.
///
/// These protect the regression surface: the wiring between Gemma's
/// tool-call output and iOS side-effects is fragile (we had a real
/// bug where the parser + registry existed but were never called).
/// A single failing test here is the clearest signal that the brain
/// has disconnected again.
final class SkillPipelineIntegrationTests: XCTestCase {

    // MARK: - Stub skill

    /// Records every invocation so tests can assert on what was called.
    @MainActor
    final class StubSkill: Skill {
        let name: String
        let description: String
        let parametersSchema: String
        private(set) var invocations: [[String: AnyCodable]] = []
        private let response: String

        init(name: String = "test_skill",
             description: String = "test",
             parametersSchema: String = #"{"type":"object"}"#,
             response: String = "stub success") {
            self.name = name
            self.description = description
            self.parametersSchema = parametersSchema
            self.response = response
        }

        func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
            invocations.append(parameters)
            return .success(response)
        }
    }

    // MARK: - SkillParser path

    func testParserHandlesStrictJSON() {
        let parser = SkillParser()
        let call = parser.parse(#"{"tool":"create_reminder","parameters":{"title":"Call Mom"}}"#)
        XCTAssertNotNil(call)
        XCTAssertEqual(call?.tool, "create_reminder")
        XCTAssertEqual(call?.parameters["title"]?.stringValue, "Call Mom")
    }

    func testParserRecoversFromProseWrapping() {
        // This was the silent-failure mode — Gemma wrapped JSON in
        // prose and the old strict parser returned nil.
        let parser = SkillParser()
        let output = """
        Sure, I'll create that reminder for you.
        {"tool":"create_reminder","parameters":{"title":"Call Mom","due_date":"2026-04-24T18:00:00Z"}}
        Let me know if you need anything else!
        """
        let call = parser.parse(output)
        XCTAssertNotNil(call, "Parser must recover from prose wrapping")
        XCTAssertEqual(call?.tool, "create_reminder")
    }

    func testParserRejectsMalformedJSON() {
        let parser = SkillParser()
        XCTAssertNil(parser.parse(#"{"tool":"x""#))  // unterminated
        XCTAssertNil(parser.parse(""))
        XCTAssertNil(parser.parse("not json at all"))
    }

    func testParserRejectsNonToolJSON() {
        let parser = SkillParser()
        // Valid JSON but not a tool call — should return nil, not crash.
        XCTAssertNil(parser.parse(#"{"name":"Bob"}"#))
    }

    // MARK: - Registry dispatch

    @MainActor
    func testRegistryDispatchesToMatchingSkill() async {
        let stub = StubSkill(name: "create_reminder")
        let registry = SkillRegistry(skills: [stub])
        let call = ToolCall(tool: "create_reminder", parameters: [
            "title": AnyCodable("Test reminder"),
        ])
        let result = await registry.dispatch(call)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(stub.invocations.count, 1)
        XCTAssertEqual(stub.invocations.first?["title"]?.stringValue, "Test reminder")
    }

    @MainActor
    func testRegistryReportsUnknownSkill() async {
        let registry = SkillRegistry(skills: [])
        let call = ToolCall(tool: "nonexistent", parameters: [:])
        let result = await registry.dispatch(call)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("Unknown skill"))
    }

    @MainActor
    func testRegistryHonorsDisabledSkills() async {
        let stub = StubSkill(name: "x")
        let registry = SkillRegistry(skills: [stub])
        registry.disabledSkillNames.insert("x")
        XCTAssertEqual(registry.enabledSkills.count, 0)
    }

    // MARK: - Full chain (stub Gemma not included — this verifies
    //                     parser + registry compose correctly)

    @MainActor
    func testFullChain_parseThenDispatch() async {
        let stub = StubSkill(name: "create_reminder", response: "Reminder created: Call Mom")
        let registry = SkillRegistry(skills: [stub])
        let parser = SkillParser()

        // Simulated Gemma output with prose wrapping — covers the
        // realistic failure mode.
        let gemmaOutput = """
        Here's the reminder:
        {"tool":"create_reminder","parameters":{"title":"Call Mom","due_date":"2026-04-24T18:00:00Z"}}
        """

        guard let call = parser.parse(gemmaOutput) else {
            XCTFail("Parser failed on known-good prose-wrapped JSON")
            return
        }
        let result = await registry.dispatch(call)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(stub.invocations.count, 1)
        XCTAssertEqual(stub.invocations.first?["title"]?.stringValue, "Call Mom")
        XCTAssertTrue(result.content.contains("Reminder created"))
    }

    // MARK: - Balanced-braces helper

    func testBalancedBracesCompletes() {
        XCTAssertTrue(RAGPipeline.hasBalancedBraces(#"{"tool":"x","parameters":{}}"#))
    }

    func testBalancedBracesIncomplete() {
        XCTAssertFalse(RAGPipeline.hasBalancedBraces(#"{"tool":"x""#))
    }

    func testBalancedBracesIgnoresStrings() {
        // `}` inside string literal shouldn't close the outer object.
        XCTAssertTrue(RAGPipeline.hasBalancedBraces(#"{"title":"} nope"}"#))
    }
}
