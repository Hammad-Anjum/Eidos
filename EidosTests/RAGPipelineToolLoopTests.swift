import XCTest
@testable import Eidos

/// Regression tests for the RAG pipeline's tool-call detection + schema
/// building. These protect the "reminders actually work" path — if any
/// of these fail, Eidos silently falls back to chat text and user
/// actions stop executing.
final class RAGPipelineToolLoopTests: XCTestCase {

    // MARK: - hasBalancedBraces

    func testBalancedBracesSimple() {
        XCTAssertTrue(RAGPipeline.hasBalancedBraces(#"{"tool":"create_reminder"}"#))
    }

    func testBalancedBracesNested() {
        XCTAssertTrue(RAGPipeline.hasBalancedBraces(#"{"tool":"x","parameters":{"a":1,"b":{"c":2}}}"#))
    }

    func testBalancedBracesIncomplete() {
        XCTAssertFalse(RAGPipeline.hasBalancedBraces(#"{"tool":"create_reminder""#))
    }

    func testBalancedBracesIgnoresBracesInStrings() {
        // `}` inside a string shouldn't decrement depth.
        XCTAssertTrue(RAGPipeline.hasBalancedBraces(#"{"tool":"x","parameters":{"title":"} fake close"}}"#))
    }

    func testBalancedBracesHandlesEscapedQuotes() {
        XCTAssertTrue(RAGPipeline.hasBalancedBraces(#"{"tool":"x","parameters":{"title":"quote\"inside"}}"#))
    }

    // MARK: - SkillParser integration

    func testSkillParserAcceptsValidToolCall() {
        let parser = SkillParser()
        let call = parser.parse(#"{"tool":"create_reminder","parameters":{"title":"Call mom","due_date":"2026-04-23T18:00:00Z"}}"#)
        XCTAssertNotNil(call)
        XCTAssertEqual(call?.tool, "create_reminder")
        XCTAssertEqual(call?.parameters["title"]?.stringValue, "Call mom")
    }

    func testSkillParserRejectsPlainProseAndRecoversWrappedJSON() {
        let parser = SkillParser()
        // Plain prose is still invalid.
        XCTAssertNil(parser.parse("I'll create a reminder for you."))
        // But markdown-wrapped JSON should recover through the balanced-
        // object fallback; this is a real production failure mode.
        let wrapped = parser.parse("```json\n{\"tool\":\"x\",\"parameters\":{}}\n```")
        XCTAssertEqual(wrapped?.tool, "x")
    }

    func testSkillParserRejectsNonToolJSON() {
        let parser = SkillParser()
        // A JSON object that happens to parse but isn't a tool call
        // (no `tool` key) should return nil.
        XCTAssertNil(parser.parse(#"{"name":"Bob","age":30}"#))
    }
}
