import XCTest
@testable import Eidos

final class MarkdownBlockParserTests: XCTestCase {
    func testParsesHeadingsWithoutMarkers() {
        let blocks = MarkdownBlockParser.blocks(from: "## Summary\nAnswer")

        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "Summary"),
            .paragraph("Answer"),
        ])
    }

    func testParsesBulletsAndNumberedLists() {
        let blocks = MarkdownBlockParser.blocks(from: "- **First** item\n2. Second item")

        XCTAssertEqual(blocks, [
            .unorderedListItem("**First** item"),
            .orderedListItem(number: "2", text: "Second item"),
        ])
    }

    func testJoinsWrappedParagraphLines() {
        let blocks = MarkdownBlockParser.blocks(from: "This is one\nwrapped paragraph.")

        XCTAssertEqual(blocks, [.paragraph("This is one wrapped paragraph.")])
    }

    func testPreservesFencedCodeWithoutBackticks() {
        let blocks = MarkdownBlockParser.blocks(from: "```swift\nlet x = 1\n```")

        XCTAssertEqual(blocks, [.code("let x = 1")])
    }
}
