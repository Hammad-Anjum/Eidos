import XCTest
@testable import Eidos

final class SkillParserTests: XCTestCase {

    func testRejectsPlainText() {
        let parser = SkillParser()
        XCTAssertNil(parser.parse("hello, world"))
    }

    func testRejectsMalformedJSON() {
        let parser = SkillParser()
        XCTAssertNil(parser.parse("{not json"))
    }

    func testParsesWellFormedToolCall() {
        let parser = SkillParser()
        let call = parser.parse(#"{"tool":"add_note","parameters":{"content":"hi"}}"#)
        XCTAssertNotNil(call)
        XCTAssertEqual(call?.tool, "add_note")
    }
}
