import XCTest
import SwiftData
@testable import Eidos

/// End-to-end sanity for `ContextBuilder` + `RAGPipeline` wiring.
/// We can't load Gemma in a unit test, so we exercise `ContextBuilder`
/// directly against a real `MemoryManager` (temp dir) and a real
/// `KnowledgeRepository` (in-memory SwiftData). This catches API drift
/// between the four pieces that actually matter at runtime.
@MainActor
final class RAGIntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var memoryManager: MemoryManager!
    private var modelContainer: ModelContainer!
    private var knowledgeRepo: KnowledgeRepository!
    private var contextBuilder: ContextBuilder!

    override func setUp() async throws {
        try await super.setUp()

        // Memory store in a throw-away directory.
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eidos-rag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        memoryManager = MemoryManager(rootOverride: tempRoot)

        // In-memory SwiftData for the KB.
        let schema = Schema([
            KnowledgeEntry.self,
            EmbeddingRecord.self,
            Conversation.self,
            ConversationMessage.self,
            IngestionLog.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        let embeddingService = EmbeddingService()
        let vectorStore = VectorStore()
        let background = KnowledgeBackgroundActor(modelContainer: modelContainer)
        knowledgeRepo = KnowledgeRepository(
            modelContainer: modelContainer,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            backgroundActor: background
        )

        contextBuilder = ContextBuilder(
            memoryManager: memoryManager,
            knowledgeRepo: knowledgeRepo
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - The actual integration test

    /// 1. Seed memory with a P1 core-identity entry and a topic entry.
    /// 2. Seed the KB with a relevant note.
    /// 3. Ask `ContextBuilder.build(query:)` — verify memory AND KB
    ///    results land in the combined text block.
    /// 4. Confirm `touch` fired (lastAccessedAt advanced) — the decay
    ///    engine depends on this.
    func testBuildPullsFromBothMemoryAndKB() async throws {
        // Memory — two entries, one P1, one topic.
        let identity = MemoryEntry(
            tier: .coreIdentity,
            title: "User profile",
            body: "Name: Hissamuddin. Vegetarian.",
            priority: .p1,
            lastAccessedAt: Date(timeIntervalSinceNow: -1000)
        )
        let topic = MemoryEntry(
            tier: .topic,
            title: "Dog's vet appointment",
            body: "Max sees Dr. Patel every 6 months.",
            priority: .p3,
            lastAccessedAt: Date(timeIntervalSinceNow: -500)
        )
        _ = try await memoryManager.save(identity)
        _ = try await memoryManager.save(topic)

        // KB — one entry the query should match via keyword.
        _ = try await knowledgeRepo.insert(
            content: "Max's next vet visit is April 22 at 3pm.",
            source: .note
        )

        // Build the context block for a related query. The keyword
        // fallback in KnowledgeRepository.search uses `localizedStandardContains`,
        // so the query has to appear verbatim in the entry text.
        let result = await contextBuilder.build(query: "vet visit")

        // Memory section
        XCTAssertTrue(result.text.contains("What I remember"))
        XCTAssertTrue(result.text.contains("User profile"))
        XCTAssertTrue(result.text.contains("Dog's vet appointment"))
        // KB section
        XCTAssertTrue(result.text.contains("From your notes"))
        XCTAssertTrue(result.text.contains("April 22"))

        // Memory was touched — lastAccessedAt moved forward.
        let refreshed = try await memoryManager.load(id: identity.id)
        XCTAssertGreaterThan(refreshed!.lastAccessedAt, identity.lastAccessedAt)
    }

    func testBuildDegradesWhenMemoryIsEmpty() async {
        let result = await contextBuilder.build(query: "anything")
        XCTAssertFalse(result.text.contains("What I remember"))
        XCTAssertFalse(result.text.contains("From your notes"))
        XCTAssertTrue(result.text.isEmpty)
    }

    func testBuildRespectsByteBudget() async throws {
        // Fill memory with lots of entries; assert total output ≤ budget.
        for i in 0..<10 {
            _ = try await memoryManager.save(MemoryEntry(
                tier: .topic,
                title: "note \(i)",
                body: String(repeating: "x", count: 500)
            ))
        }
        let result = await contextBuilder.build(query: "q", maxChars: 1200)
        XCTAssertLessThanOrEqual(result.text.count, 1200)
    }
}
