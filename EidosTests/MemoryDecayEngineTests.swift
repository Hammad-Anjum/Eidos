import XCTest
@testable import Eidos

final class MemoryDecayEngineTests: XCTestCase {

    private var tempRoot: URL!
    private var manager: MemoryManager!
    private var engine: MemoryDecayEngine!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eidos-decay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        manager = MemoryManager(rootOverride: tempRoot)
        engine = MemoryDecayEngine(manager: manager)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - No-op cases

    func testNoActionWhenEverythingIsFresh() async throws {
        try await manager.save(MemoryEntry(
            tier: .topic, title: "fresh", body: "",
            priority: .p3, lastAccessedAt: Date()))

        let report = try await engine.runOnce()
        XCTAssertTrue(report.isNoop)
    }

    func testP1NeverDecays() async throws {
        try await manager.save(MemoryEntry(
            tier: .coreIdentity, title: "me", body: "",
            priority: .p1,
            lastAccessedAt: Date(timeIntervalSinceNow: -100 * 86_400 * 365)))

        let report = try await engine.runOnce()
        XCTAssertTrue(report.isNoop)

        let reloaded = try await manager.load(id: (await manager.index.all).first!.id)
        XCTAssertEqual(reloaded?.priority, .p1)
    }

    // MARK: - Demotion

    func testP2DemotesToP3AfterStaleWindow() async throws {
        let saved = try await manager.save(MemoryEntry(
            tier: .topic, title: "old deadline", body: "",
            priority: .p2,
            lastAccessedAt: Date(timeIntervalSinceNow: -20 * 86_400)))  // > 14 d

        let report = try await engine.runOnce()
        XCTAssertEqual(report.demoted, [saved.id])

        let reloaded = try await manager.load(id: saved.id)
        XCTAssertEqual(reloaded?.priority, .p3)
    }

    func testP3DemotesToP4() async throws {
        let saved = try await manager.save(MemoryEntry(
            tier: .topic, title: "stale note", body: "",
            priority: .p3,
            lastAccessedAt: Date(timeIntervalSinceNow: -70 * 86_400)))  // > 60 d

        _ = try await engine.runOnce()
        let reloaded = try await manager.load(id: saved.id)
        XCTAssertEqual(reloaded?.priority, .p4)
    }

    // MARK: - Archival

    func testP4ArchivesAndBumpsToP5() async throws {
        let saved = try await manager.save(MemoryEntry(
            tier: .topic, title: "dusty", body: "",
            priority: .p4,
            lastAccessedAt: Date(timeIntervalSinceNow: -200 * 86_400)))  // > 180 d

        let report = try await engine.runOnce()
        XCTAssertEqual(report.archived, [saved.id])

        let reloaded = try await manager.load(id: saved.id)
        XCTAssertEqual(reloaded?.tier, .archive)
        XCTAssertEqual(reloaded?.priority, .p5)
    }

    // MARK: - Eviction

    func testP5EvictsWhenYearOld() async throws {
        let saved = try await manager.save(MemoryEntry(
            tier: .archive, title: "ancient", body: "",
            priority: .p5,
            lastAccessedAt: Date(timeIntervalSinceNow: -400 * 86_400)))  // > 365 d

        let report = try await engine.runOnce()
        XCTAssertEqual(report.evicted, [saved.id])

        let reloaded = try await manager.load(id: saved.id)
        XCTAssertNil(reloaded)
    }

    // MARK: - Mixed pass

    func testMixedPassAppliesAllRules() async throws {
        let fresh = try await manager.save(MemoryEntry(
            tier: .topic, title: "fresh", body: "",
            priority: .p3, lastAccessedAt: Date()))
        let toDemote = try await manager.save(MemoryEntry(
            tier: .topic, title: "demote", body: "",
            priority: .p2,
            lastAccessedAt: Date(timeIntervalSinceNow: -30 * 86_400)))
        let toArchive = try await manager.save(MemoryEntry(
            tier: .topic, title: "archive", body: "",
            priority: .p4,
            lastAccessedAt: Date(timeIntervalSinceNow: -200 * 86_400)))

        let report = try await engine.runOnce()

        XCTAssertFalse(report.demoted.contains(fresh.id))
        XCTAssertTrue(report.demoted.contains(toDemote.id))
        XCTAssertTrue(report.archived.contains(toArchive.id))
    }
}
