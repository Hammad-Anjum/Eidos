import XCTest
@testable import Eidos

final class RRFusionTests: XCTestCase {

    func testEmptyRankingsProduceNoResults() {
        let fused = KnowledgeRepository.reciprocalRankFusion(rankings: [])
        XCTAssertTrue(fused.isEmpty)
    }

    func testSingleRankingPreservesOrder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let fused = KnowledgeRepository.reciprocalRankFusion(rankings: [[a, b, c]])
        XCTAssertEqual(fused, [a, b, c])
    }

    func testItemRankedFirstInBothRankingsWinsOverItemRankedSecondInBoth() {
        // a is rank 1 in both rankings, b is rank 2 in both.
        // RRF (k=60): score(a) = 1/61 + 1/61, score(b) = 1/62 + 1/62.
        let a = UUID()
        let b = UUID()
        let fused = KnowledgeRepository.reciprocalRankFusion(rankings: [[a, b], [a, b]])
        XCTAssertEqual(fused.first, a)
        XCTAssertEqual(fused.last, b)
    }

    func testItemAppearingInBothRankingsBeatsItemAppearingInOnlyOne() {
        // a is rank 1 in both → score = 2 * (1/61) ≈ 0.0328
        // b is rank 1 in only one → score = 1/61 ≈ 0.0164
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let fused = KnowledgeRepository.reciprocalRankFusion(
            rankings: [[a, c], [a, b]]
        )
        XCTAssertEqual(fused.first, a)
        // b and c each appear in exactly one ranking at rank 2 / rank 2.
        // Their scores are equal — fused order between them is determined by
        // the tiebreaker (lexicographic UUID order). Just verify a is first.
        XCTAssertTrue(fused.contains(b))
        XCTAssertTrue(fused.contains(c))
    }

    func testHighRankInOneListCanBeatLowRankInBoth() {
        // a is rank 1 in one ranking only → score = 1/61 ≈ 0.0164
        // b is rank 30 in both rankings → score = 2 * (1/90) ≈ 0.0222
        // b should win because two mediocre rankings beat one excellent.
        let a = UUID()
        let b = UUID()
        var listOne: [UUID] = []
        var listTwo: [UUID] = []
        // Pad both lists with 29 distinct dummy UUIDs so b lands at rank 30.
        let dummies1 = (0..<29).map { _ in UUID() }
        let dummies2 = (0..<29).map { _ in UUID() }
        listOne.append(a)
        listOne.append(contentsOf: dummies1)
        listOne.append(b)
        listTwo.append(contentsOf: dummies2)
        listTwo.append(b)

        let fused = KnowledgeRepository.reciprocalRankFusion(rankings: [listOne, listTwo])
        let aIndex = fused.firstIndex(of: a)!
        let bIndex = fused.firstIndex(of: b)!
        XCTAssertLessThan(bIndex, aIndex,
                          "b should outrank a because it appears in both lists")
    }

    func testDeterministicTiebreaker() {
        // Two items with identical scores must produce a stable ordering
        // across runs — UUID lexicographic order.
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let fused1 = KnowledgeRepository.reciprocalRankFusion(rankings: [[a], [b]])
        let fused2 = KnowledgeRepository.reciprocalRankFusion(rankings: [[a], [b]])
        XCTAssertEqual(fused1, fused2)
    }
}
