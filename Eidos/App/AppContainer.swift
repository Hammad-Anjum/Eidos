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
    let memoryManager: MemoryManager
    let memoryDecayEngine: MemoryDecayEngine
    let memoryCrystallizer: MemoryCrystallizer
    let appActionRegistry: AppActionRegistry
    let healthSource: HealthSource
    let notificationScheduler: NotificationScheduler
    let proactiveDigestGenerator: ProactiveDigestGenerator
    let locationSource: LocationSource
    let motionSource: MotionSource
    let liveActivityManager: LiveActivityManager
    var isBootstrapped = false

    init() throws {
        let schema = Schema([
            KnowledgeEntry.self,
            EmbeddingRecord.self,
            Conversation.self,
            ConversationMessage.self,
            IngestionLog.self,
        ])

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

        let memoryManager = MemoryManager()
        let digestGenerator = DigestGenerator(
            calendarSource: calendarSource,
            knowledgeRepo: knowledgeRepo,
            memoryManager: memoryManager,
            gemma: gemma
        )

        let appActionRegistry = AppActionRegistry()

        let skills: [any Skill] = [
            CalendarSkill(source: calendarSource),
            RemindersSkill(source: calendarSource),
            CreateReminderSkill(source: calendarSource),
            ContactsSkill(source: contactsSource),
            SearchKBSkill(repo: knowledgeRepo),
            AddNoteSkill(repo: knowledgeRepo),
            DigestSkill(digestGenerator: digestGenerator),
            SendWhatsAppSkill(registry: appActionRegistry),
            SendSMSSkill(registry: appActionRegistry),
            SendEmailSkill(registry: appActionRegistry),
            PlaceCallSkill(registry: appActionRegistry),
            NavigateSkill(registry: appActionRegistry),
            RequestRideSkill(registry: appActionRegistry),
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
        self.memoryManager = memoryManager
        self.memoryDecayEngine = MemoryDecayEngine(manager: memoryManager)
        self.memoryCrystallizer = MemoryCrystallizer(gemma: gemma, manager: memoryManager)
        self.appActionRegistry = appActionRegistry
        let healthSource = HealthSource()
        self.healthSource = healthSource
        self.notificationScheduler = NotificationScheduler()
        self.locationSource = LocationSource()
        self.motionSource = MotionSource()
        self.liveActivityManager = LiveActivityManager()
        self.proactiveDigestGenerator = ProactiveDigestGenerator(
            calendarSource: calendarSource,
            memoryManager: memoryManager,
            healthSource: healthSource,
            gemma: gemma
        )
        self.ragPipeline = RAGPipeline(
            gemma: gemma,
            knowledgeRepo: knowledgeRepo,
            memoryManager: memoryManager,
            skillRegistry: skillRegistry
        )
        self.digestGenerator = digestGenerator
        self.ingestionCoordinator = IngestionCoordinator(repo: knowledgeRepo)
        self.modelDownloader = ModelDownloader(gemma: gemma)
    }

    /// Async setup — called from `.task` on the root view.
    ///
    /// Order matters:
    /// 1. Load vector index from SwiftData
    /// 2. Load embedding model (if assets available)
    /// 3. If a model was previously downloaded, warm it up
    /// 4. Arm EgressGuard — all outbound traffic blocked from here on
    func bootstrap() async {
        await knowledgeRepo.loadVectorStoreFromDB()
        try? await memoryManager.rebuildIndex()

        // NLContextualEmbedding asset download fails in the iOS Simulator
        // (permission denied on `/var/db/com.apple.naturallanguaged`). On
        // device, Apple's CDN delivers the asset on first launch.
        #if !targetEnvironment(simulator)
        if await !embeddingService.hasAssets() {
            try? await embeddingService.ensureAssetsAvailable()
        }
        if await embeddingService.hasAssets() {
            try? await embeddingService.load()
        }
        #endif

        // Load the cached model. If the files are missing (user wiped
        // Documents, etc.) clear the flag so onboarding shows again.
        if modelDownloader.isModelDownloaded {
            do {
                try await gemma.load(variant: modelDownloader.selectedVariant)
            } catch {
                UserDefaults.standard.set(false, forKey: "eidos.modelDownloaded")
            }
        }

        // If the user has morning digest enabled, make sure it's scheduled.
        // Safe to call repeatedly — it removes+re-adds the pending request.
        if notificationScheduler.digestEnabled {
            await notificationScheduler.scheduleMorningDigest()
        }

        EgressGuard.install()
        isBootstrapped = true
    }
}
