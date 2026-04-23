import XCTest
@testable import Eidos

/// Renderer tests. Integration with `KnowledgeRepository` is exercised at
/// the RAG-pipeline / on-device level, not here.
final class ContextBuilderTests: XCTestCase {

    // MARK: - Memory rendering

    func testEmptyInputsProduceEmptyString() {
        XCTAssertTrue(ContextBuilder.renderMemory([], maxChars: 1000).isEmpty)
        XCTAssertTrue(ContextBuilder.renderKB([], maxChars: 1000).isEmpty)
    }

    func testMemoryRenderIncludesHeader() {
        let entry = MemoryEntry(tier: .topic, title: "Loves coffee", body: "Espresso at 7am")
        let out = ContextBuilder.renderMemory([entry], maxChars: 1000)
        XCTAssertTrue(out.contains("What I remember"))
        XCTAssertTrue(out.contains("Loves coffee"))
        XCTAssertTrue(out.contains("Espresso at 7am"))
    }

    func testMemoryRenderStopsAtBudget() {
        let longBody = String(repeating: "a", count: 500)
        let entries = (0..<10).map {
            MemoryEntry(tier: .topic, title: "entry \($0)", body: longBody)
        }
        // Budget of 1000 chars only fits ~2 entries.
        let out = ContextBuilder.renderMemory(entries, maxChars: 1000)
        XCTAssertTrue(out.contains("entry 0"))
        XCTAssertFalse(out.contains("entry 9"), "Over-budget entries should be dropped")
        XCTAssertLessThanOrEqual(out.count, 1000)
    }

    func testMemoryRenderPreservesOrder() {
        let a = MemoryEntry(tier: .coreIdentity, title: "first", body: "a")
        let b = MemoryEntry(tier: .topic,        title: "second", body: "b")
        let c = MemoryEntry(tier: .topic,        title: "third", body: "c")
        let out = ContextBuilder.renderMemory([a, b, c], maxChars: 1000)

        guard let ra = out.range(of: "first"),
              let rb = out.range(of: "second"),
              let rc = out.range(of: "third") else {
            return XCTFail("titles should all be present")
        }
        XCTAssertLessThan(ra.lowerBound, rb.lowerBound)
        XCTAssertLessThan(rb.lowerBound, rc.lowerBound)
    }

    // MARK: - KB rendering

    func testKBRenderIncludesHeaderAndSnippets() {
        let hits = [
            KnowledgeRepository.SearchHit(entryID: UUID(), score: 1.0, snippet: "note about dentist"),
            KnowledgeRepository.SearchHit(entryID: UUID(), score: 0.5, snippet: "note about dog"),
        ]
        let out = ContextBuilder.renderKB(hits, maxChars: 1000)
        XCTAssertTrue(out.contains("From your notes"))
        XCTAssertTrue(out.contains("dentist"))
        XCTAssertTrue(out.contains("dog"))
    }

    func testKBRenderRespectsBudget() {
        let snippet = String(repeating: "x", count: 400)
        let hits = (0..<10).map {
            KnowledgeRepository.SearchHit(entryID: UUID(), score: Float($0), snippet: "\($0) \(snippet)")
        }
        let out = ContextBuilder.renderKB(hits, maxChars: 800)
        XCTAssertLessThanOrEqual(out.count, 800)
    }

    func testRenderWithZeroBudgetReturnsEmpty() {
        let entry = MemoryEntry(tier: .topic, title: "t", body: "b")
        XCTAssertTrue(ContextBuilder.renderMemory([entry], maxChars: 0).isEmpty)
        let hits = [KnowledgeRepository.SearchHit(entryID: UUID(), score: 1, snippet: "x")]
        XCTAssertTrue(ContextBuilder.renderKB(hits, maxChars: 0).isEmpty)
    }
}
