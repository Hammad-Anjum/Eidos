import XCTest
@testable import Eidos

final class KnowledgeEntryTests: XCTestCase {

    func testContentHashIsStable() {
        let a = KnowledgeEntry.hash(of: "hello world")
        let b = KnowledgeEntry.hash(of: "hello world")
        XCTAssertEqual(a, b)
    }

    func testContentHashDiffersForDifferentContent() {
        let a = KnowledgeEntry.hash(of: "hello world")
        let b = KnowledgeEntry.hash(of: "hello worldd")
        XCTAssertNotEqual(a, b)
    }

    func testContentHashIsSHA256Length() {
        // SHA256 hex = 64 characters
        XCTAssertEqual(KnowledgeEntry.hash(of: "x").count, 64)
    }
}
