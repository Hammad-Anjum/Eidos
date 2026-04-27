import XCTest
@testable import Eidos

/// Verifies that `remember_fact` writes into the durable memory system
/// (not the retrieved-on-demand KB). Distinction matters: short
/// personal truths ("user's partner is Sana") should live in memory
/// where they're always in context, not in the KB where they require
/// a retrieval hit to surface.
final class RememberFactSkillTests: XCTestCase {

    private var tempRoot: URL!
    private var manager: MemoryManager!
    private var skill: RememberFactSkill!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eidos-remember-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        manager = MemoryManager(rootOverride: tempRoot)
        skill = RememberFactSkill(manager: manager)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    func testWritesFactToMemoryTier() async throws {
        let result = await skill.invoke(parameters: [
            "title": AnyCodable("Likes olives"),
            "body": AnyCodable("User prefers Kalamata olives on salads."),
            "tier": AnyCodable("topic"),
            "priority": AnyCodable(3),
        ])
        XCTAssertFalse(result.isError, "Skill should succeed with valid params")

        // Rebuild the index from disk and confirm the record appears.
        try await manager.rebuildIndex()
        let topicRecords = await manager.index.records(tier: .topic)
        XCTAssertEqual(topicRecords.count, 1)
        XCTAssertEqual(topicRecords.first?.title, "Likes olives")
    }

    func testFailsWithoutTitle() async {
        let result = await skill.invoke(parameters: [
            "body": AnyCodable("a body but no title"),
        ])
        XCTAssertTrue(result.isError, "Missing title should fail")
    }

    func testFailsWithoutBody() async {
        let result = await skill.invoke(parameters: [
            "title": AnyCodable("just a title"),
        ])
        XCTAssertTrue(result.isError, "Missing body should fail")
    }

    func testDefaultsToTopicTierAndP3() async throws {
        _ = await skill.invoke(parameters: [
            "title": AnyCodable("t"),
            "body": AnyCodable("b"),
        ])
        try await manager.rebuildIndex()
        let all = await manager.index.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.tier, .topic)
        XCTAssertEqual(all.first?.priority, .p3)
    }

    func testRespectsCoreIdentityTierWhenRequested() async throws {
        _ = await skill.invoke(parameters: [
            "title": AnyCodable("Wife's name"),
            "body": AnyCodable("Sana."),
            "tier": AnyCodable("core_identity"),
            "priority": AnyCodable(1),
        ])
        try await manager.rebuildIndex()
        let core = await manager.index.records(tier: .coreIdentity)
        XCTAssertEqual(core.count, 1)
        XCTAssertEqual(core.first?.priority, .p1)
    }
}
