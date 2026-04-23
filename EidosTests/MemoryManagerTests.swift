import XCTest
@testable import Eidos

final class MemoryManagerTests: XCTestCase {

    private var tempRoot: URL!
    private var manager: MemoryManager!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eidos-memory-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        manager = MemoryManager(rootOverride: tempRoot)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Save / load

    func testSaveAndLoadRoundTrip() async throws {
        let original = MemoryEntry(
            tier: .topic,
            title: "Work preferences",
            body: "- likes mornings\n- hates meetings after 4pm",
            priority: .p2,
            tags: ["work", "preferences"]
        )
        let saved = try await manager.save(original)

        let loaded = try await manager.load(id: saved.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, saved.id)
        XCTAssertEqual(loaded?.title, "Work preferences")
        XCTAssertEqual(loaded?.tier, .topic)
        XCTAssertEqual(loaded?.priority, .p2)
        XCTAssertEqual(loaded?.tags, ["work", "preferences"])
        XCTAssertTrue(loaded?.body.contains("likes mornings") ?? false)
    }

    func testSaveTouchesUpdatedAt() async throws {
        let entry = MemoryEntry(
            tier: .topic, title: "X", body: "y",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let saved = try await manager.save(entry)
        XCTAssertGreaterThan(saved.updatedAt, Date(timeIntervalSince1970: 0))
    }

    func testLoadReturnsNilForMissing() async throws {
        let result = try await manager.load(id: UUID())
        XCTAssertNil(result)
    }

    // MARK: - List

    func testListReturnsAllEntriesInTier() async throws {
        try await manager.save(MemoryEntry(tier: .topic, title: "A", body: ""))
        try await manager.save(MemoryEntry(tier: .topic, title: "B", body: ""))
        try await manager.save(MemoryEntry(tier: .coreIdentity, title: "C", body: ""))

        let topics = try await manager.list(tier: .topic)
        let core = try await manager.list(tier: .coreIdentity)
        XCTAssertEqual(topics.count, 2)
        XCTAssertEqual(core.count, 1)
        XCTAssertEqual(core.first?.title, "C")
    }

    func testListSortsByLastAccessedDesc() async throws {
        let old = MemoryEntry(
            tier: .topic, title: "old", body: "",
            lastAccessedAt: Date(timeIntervalSinceNow: -1000)
        )
        let recent = MemoryEntry(
            tier: .topic, title: "recent", body: "",
            lastAccessedAt: Date()
        )
        try await manager.save(old)
        try await manager.save(recent)

        let listed = try await manager.list(tier: .topic)
        XCTAssertEqual(listed.first?.title, "recent")
        XCTAssertEqual(listed.last?.title, "old")
    }

    // MARK: - Delete / move / touch

    func testDeleteRemovesFile() async throws {
        let saved = try await manager.save(MemoryEntry(tier: .topic, title: "X", body: ""))
        try await manager.delete(id: saved.id)
        let result = try await manager.load(id: saved.id)
        XCTAssertNil(result)
    }

    func testDeleteThrowsWhenMissing() async {
        do {
            try await manager.delete(id: UUID())
            XCTFail("expected notFound")
        } catch MemoryManagerError.notFound {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testTouchUpdatesLastAccessed() async throws {
        let start = Date(timeIntervalSinceNow: -1000)
        var entry = MemoryEntry(
            tier: .topic, title: "X", body: "",
            lastAccessedAt: start
        )
        entry = try await manager.save(entry)
        try await manager.touch(id: entry.id)

        let reloaded = try await manager.load(id: entry.id)
        XCTAssertGreaterThan(reloaded!.lastAccessedAt, start)
    }

    func testMoveBetweenTiers() async throws {
        let saved = try await manager.save(MemoryEntry(tier: .topic, title: "X", body: "body"))
        try await manager.move(id: saved.id, to: .archive)

        let topicList = try await manager.list(tier: .topic)
        let archiveList = try await manager.list(tier: .archive)
        XCTAssertTrue(topicList.isEmpty)
        XCTAssertEqual(archiveList.count, 1)
        XCTAssertEqual(archiveList.first?.tier, .archive)
        XCTAssertEqual(archiveList.first?.body, "body")
    }

    // MARK: - Frontmatter round-trip

    func testFrontmatterRoundTripPreservesAllFields() throws {
        let original = MemoryEntry(
            id: UUID(),
            tier: .activePriorities,
            title: "Has \"quotes\" and, commas",
            body: "# Heading\n\nContent with `code` and *emphasis*.",
            priority: .p1,
            tags: ["tag one", "quoted\"tag", "simple"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_001_000),
            lastAccessedAt: Date(timeIntervalSince1970: 1_700_002_000)
        )
        let rendered = MemoryFrontmatter.render(original)
        let parsed = try MemoryFrontmatter.parse(rendered)

        XCTAssertEqual(parsed.id, original.id)
        XCTAssertEqual(parsed.tier, original.tier)
        XCTAssertEqual(parsed.title, original.title)
        XCTAssertEqual(parsed.priority, original.priority)
        XCTAssertEqual(parsed.tags.sorted(), original.tags.sorted())
        XCTAssertEqual(parsed.body, original.body)
        // Dates round-trip to within 1 second (ISO8601 precision).
        XCTAssertEqual(parsed.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970, accuracy: 1)
    }

    func testFrontmatterRejectsMissingDelimiters() {
        XCTAssertThrowsError(try MemoryFrontmatter.parse("no frontmatter here"))
    }

    func testFrontmatterRejectsMalformedPriority() {
        let raw = """
        ---
        id: \(UUID().uuidString)
        title: "x"
        tier: topic
        priority: banana
        tags: []
        created_at: 2026-01-01T00:00:00Z
        updated_at: 2026-01-01T00:00:00Z
        last_accessed_at: 2026-01-01T00:00:00Z
        ---

        body
        """
        XCTAssertThrowsError(try MemoryFrontmatter.parse(raw))
    }
}
