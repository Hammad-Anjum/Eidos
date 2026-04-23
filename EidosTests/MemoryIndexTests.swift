import XCTest
@testable import Eidos

final class MemoryIndexTests: XCTestCase {

    private var tempRoot: URL!
    private var manager: MemoryManager!
    private var index: MemoryIndex { manager.index }

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eidos-memory-idx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        manager = MemoryManager(rootOverride: tempRoot)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Sync with disk

    func testSaveRegistersInIndex() async throws {
        let saved = try await manager.save(
            MemoryEntry(tier: .topic, title: "A", body: "")
        )
        let count = await index.count
        XCTAssertEqual(count, 1)
        let all = await index.all
        XCTAssertEqual(all.first?.id, saved.id)
    }

    func testDeleteRemovesFromIndex() async throws {
        let saved = try await manager.save(
            MemoryEntry(tier: .topic, title: "A", body: "")
        )
        try await manager.delete(id: saved.id)
        let count = await index.count
        XCTAssertEqual(count, 0)
    }

    func testMoveKeepsSingleRecordWithNewTier() async throws {
        let saved = try await manager.save(
            MemoryEntry(tier: .topic, title: "A", body: "")
        )
        try await manager.move(id: saved.id, to: .archive)

        let count = await index.count
        XCTAssertEqual(count, 1, "Move shouldn't duplicate records.")
        let tier = await index.records(tier: .archive).first?.tier
        XCTAssertEqual(tier, .archive)
    }

    func testTouchUpdatesIndexLastAccessed() async throws {
        let start = Date(timeIntervalSinceNow: -1000)
        let saved = try await manager.save(
            MemoryEntry(tier: .topic, title: "A", body: "",
                        lastAccessedAt: start)
        )
        try await manager.touch(id: saved.id)

        let rec = await index.records(tier: .topic).first
        XCTAssertGreaterThan(rec?.lastAccessedAt ?? .distantPast, start)
    }

    // MARK: - Rebuild

    func testRebuildPopulatesFromDisk() async throws {
        try await manager.save(MemoryEntry(tier: .topic, title: "A", body: ""))
        try await manager.save(MemoryEntry(tier: .coreIdentity, title: "B", body: ""))
        try await manager.save(MemoryEntry(tier: .archive, title: "C", body: ""))

        // Fresh manager over the same disk: index starts empty.
        let fresh = MemoryManager(rootOverride: tempRoot)
        let beforeRebuild = await fresh.index.count
        XCTAssertEqual(beforeRebuild, 0)

        try await fresh.rebuildIndex()
        let afterRebuild = await fresh.index.count
        XCTAssertEqual(afterRebuild, 3)
    }

    // MARK: - Queries

    func testRecordsByTier() async throws {
        try await manager.save(MemoryEntry(tier: .topic, title: "t1", body: ""))
        try await manager.save(MemoryEntry(tier: .topic, title: "t2", body: ""))
        try await manager.save(MemoryEntry(tier: .coreIdentity, title: "c1", body: ""))

        let topics = await index.records(tier: .topic)
        let core = await index.records(tier: .coreIdentity)
        XCTAssertEqual(topics.count, 2)
        XCTAssertEqual(core.count, 1)
    }

    func testRecordsByTag() async throws {
        try await manager.save(MemoryEntry(
            tier: .topic, title: "A", body: "", tags: ["work", "urgent"]))
        try await manager.save(MemoryEntry(
            tier: .topic, title: "B", body: "", tags: ["personal"]))
        try await manager.save(MemoryEntry(
            tier: .topic, title: "C", body: "", tags: ["work"]))

        let work = await index.records(withTag: "work")
        let urgent = await index.records(withTag: "urgent")
        XCTAssertEqual(work.count, 2)
        XCTAssertEqual(urgent.count, 1)
    }

    func testRecordsByPriority() async throws {
        try await manager.save(MemoryEntry(tier: .topic, title: "hi", body: "", priority: .p1))
        try await manager.save(MemoryEntry(tier: .topic, title: "mid", body: "", priority: .p3))
        try await manager.save(MemoryEntry(tier: .topic, title: "low", body: "", priority: .p3))

        let p1 = await index.records(priority: .p1)
        let p3 = await index.records(priority: .p3)
        XCTAssertEqual(p1.count, 1)
        XCTAssertEqual(p3.count, 2)
    }

    func testTopKReturnsHottestFirst() async throws {
        try await manager.save(MemoryEntry(
            tier: .topic, title: "old", body: "",
            lastAccessedAt: Date(timeIntervalSinceNow: -3000)))
        try await manager.save(MemoryEntry(
            tier: .topic, title: "mid", body: "",
            lastAccessedAt: Date(timeIntervalSinceNow: -1000)))
        try await manager.save(MemoryEntry(
            tier: .topic, title: "hot", body: "",
            lastAccessedAt: Date()))

        let top2 = await index.topK(2)
        XCTAssertEqual(top2.map(\.title), ["hot", "mid"])
    }

    func testStaleFilter() async throws {
        try await manager.save(MemoryEntry(
            tier: .topic, title: "fresh", body: "",
            lastAccessedAt: Date()))
        try await manager.save(MemoryEntry(
            tier: .topic, title: "stale", body: "",
            lastAccessedAt: Date(timeIntervalSinceNow: -30 * 86_400)))

        let stale = await index.stale(olderThanDays: 14)
        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale.first?.title, "stale")
    }
}
