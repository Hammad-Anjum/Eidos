import Foundation
import SwiftData

@MainActor
@Observable
final class AppContainer {

    let modelContainer: ModelContainer
    let gemma: GemmaSession
    let embeddingService: EmbeddingService
    let vectorStore: VectorStore
    let knowledgeBackgroundActor: KnowledgeBackgroundActor
    let calendarSource: CalendarSource
    let contactsSource: ContactsSource
    let knowledgeRepo: KnowledgeRepository
    let skillRegistry: SkillRegistry
    let ragPipeline: RAGPipeline
    let digestGenerator: DigestGenerator
    let ingestionCoordinator: IngestionCoordinator
    let modelDownloader: ModelDownloader

    init() throws {
        let schema = Schema([
            KnowledgeEntry.self,
            EmbeddingRecord.self,
            Conversation.self,
            ConversationMessage.self,
            IngestionLog.self,
        ])

        // B6: force complete file protection on the SwiftData store so
        // the knowledge base is unreadable while the device is locked.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        self.modelContainer = try ModelContainer(for: schema, configurations: config)

        let gemma = GemmaSession()
        let embeddingService = EmbeddingService()
        let vectorStore = VectorStore()
        let knowledgeBackgroundActor = KnowledgeBackgroundActor(modelContainer: modelContainer)
        let calendarSource = CalendarSource()
        let contactsSource = ContactsSource()

        let knowledgeRepo = KnowledgeRepository(
            modelContainer: modelContainer,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            backgroundActor: knowledgeBackgroundActor
        )

        let skills: [any Skill] = [
            CalendarSkill(source: calendarSource),
            RemindersSkill(source: calendarSource),
            ContactsSkill(source: contactsSource),
            SearchKBSkill(repo: knowledgeRepo),
            AddNoteSkill(repo: knowledgeRepo),
            DigestSkill(),
        ]
        let skillRegistry = SkillRegistry(skills: skills)

        self.gemma = gemma
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.knowledgeBackgroundActor = knowledgeBackgroundActor
        self.calendarSource = calendarSource
        self.contactsSource = contactsSource
        self.knowledgeRepo = knowledgeRepo
        self.skillRegistry = skillRegistry
        self.ragPipeline = RAGPipeline(
            gemma: gemma,
            knowledgeRepo: knowledgeRepo,
            skillRegistry: skillRegistry
        )
        self.digestGenerator = DigestGenerator(
            calendarSource: calendarSource,
            knowledgeRepo: knowledgeRepo,
            gemma: gemma
        )
        self.ingestionCoordinator = IngestionCoordinator(repo: knowledgeRepo)
        self.modelDownloader = ModelDownloader()
    }

    /// Kicks off work that requires async setup — called from `.task` on
    /// the root view so it never blocks the window scene.
    ///
    /// Per plan.md §A3-asset, the order is deliberate:
    ///
    /// 1. Load the in-memory vector index from the SwiftData store.
    /// 2. If the NLContextualEmbedding asset isn't cached yet, download it
    ///    from Apple's CDN. This is the ONE moment in the app's lifetime
    ///    where we allow that specific egress, and it happens BEFORE
    ///    EgressGuard is armed.
    /// 3. Load the embedding model into memory.
    /// 4. If the Gemma model is already on disk, warm it up. (Actual
    ///    model download goes through ModelDownloader, which temporarily
    ///    opens the Hugging Face host through EgressGuard.)
    /// 5. Arm EgressGuard with the permanent allowlist. From this point
    ///    on, all outbound traffic is blocked unless the guard explicitly
    ///    opens a hole (currently only ModelDownloader does this).
    func bootstrap() async {
        await knowledgeRepo.loadVectorStoreFromDB()

        // A3-asset: download embedding weights while the network is still
        // usable. Failures are non-fatal — the user can retry from Settings
        // once they're online. Semantic search will fall back to keyword
        // search via KnowledgeRepository.search until this succeeds.
        if await !embeddingService.hasAssets() {
            try? await embeddingService.ensureAssetsAvailable()
        }
        try? await embeddingService.load()

        if let path = modelDownloader.modelPath(for: .e4b) {
            try? await gemma.load(modelPath: path.path, config: ModelConfig())
        }

        // B14: arm the egress guard after asset bring-up so the NL asset
        // fetch above isn't blocked on first launch.
        EgressGuard.install()
    }
}
