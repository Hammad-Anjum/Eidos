import XCTest
@testable import Eidos

final class VectorStoreTests: XCTestCase {

    func testEmptyStoreReturnsNoHits() async {
        let store = VectorStore()
        let results = await store.topK(query: [1, 0, 0], k: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testDotProductOrdering() async {
        let store = VectorStore()
        let entryA = UUID()
        let entryB = UUID()
        let entryC = UUID()

        // L2-normalised unit vectors along the three axes.
        await store.add(embeddingID: UUID(), entryID: entryA, chunkText: "x", vector: [1, 0, 0])
        await store.add(embeddingID: UUID(), entryID: entryB, chunkText: "y", vector: [0, 1, 0])
        await store.add(embeddingID: UUID(), entryID: entryC, chunkText: "z", vector: [0, 0, 1])

        let resultsX = await store.topK(query: [1, 0, 0], k: 3)
        XCTAssertEqual(resultsX.count, 3)
        XCTAssertEqual(resultsX.first?.entryID, entryA)

        let resultsY = await store.topK(query: [0, 1, 0], k: 3)
        XCTAssertEqual(resultsY.first?.entryID, entryB)

        let resultsZ = await store.topK(query: [0, 0, 1], k: 3)
        XCTAssertEqual(resultsZ.first?.entryID, entryC)
    }

    func testNearbyVectorsBeatFarVectors() async {
        let store = VectorStore()
        let near = UUID()
        let far = UUID()
        // `near` is almost aligned with the query, `far` is orthogonal.
        await store.add(embeddingID: UUID(), entryID: near, chunkText: "a", vector: [0.99, 0.14, 0])
        await store.add(embeddingID: UUID(), entryID: far, chunkText: "b", vector: [0, 1, 0])
        let results = await store.topK(query: [1, 0, 0], k: 2)
        XCTAssertEqual(results.first?.entryID, near)
        XCTAssertEqual(results.last?.entryID, far)
    }

    func testRemoveDropsAllChunksForEntry() async {
        let store = VectorStore()
        let target = UUID()
        await store.add(embeddingID: UUID(), entryID: target, chunkText: "a", vector: [1, 0, 0])
        await store.add(embeddingID: UUID(), entryID: target, chunkText: "b", vector: [0, 1, 0])
        let beforeCount = await store.count
        XCTAssertEqual(beforeCount, 2)
        await store.remove(entryID: target)
        let afterCount = await store.count
        XCTAssertEqual(afterCount, 0)
    }
}
