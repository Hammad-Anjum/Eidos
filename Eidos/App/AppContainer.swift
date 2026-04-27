import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFAudio)
import AVFAudio
#endif

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
    /// Embedding-based semantic recall over the memory store. Built
    /// in NEXT-1 (2026-04-27). Bridges EmbeddingService + VectorStore
    /// + MemoryManager so chat turns can find memories by meaning,
    /// not just keyword.
    let memoryRecall: MemoryRecallService
    let memoryDecayEngine: MemoryDecayEngine
    let memoryCrystallizer: MemoryCrystallizer
    let appActionRegistry: AppActionRegistry
    let healthSource: HealthSource
    let notificationScheduler: NotificationScheduler
    let proactiveDigestGenerator: ProactiveDigestGenerator
    let locationSource: LocationSource
    let motionSource: MotionSource
    let liveActivityManager: LiveActivityManager
    let benchmarkRunner: BenchmarkRunner
    let audioCaptureService: AudioCaptureService
    let visionCaptureService: VisionCaptureService
    let musicSource: MusicSource
    let ambientSnapshotAssembler: AmbientSnapshotAssembler
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
            RememberFactSkill(manager: memoryManager),
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
        // Embedding-based memory recall. Wires the EmbeddingService +
        // VectorStore + MemoryManager into a single semantic-recall
        // API. After this is constructed, every newly-crystallized
        // memory is auto-indexed (via attachRecallService below) and
        // RAGPipeline.chatLite calls recall() to inject relevant
        // facts into the chat prompt's <untrusted> block.
        let memoryRecall = MemoryRecallService(
            embedding: embeddingService,
            vectorStore: vectorStore,
            manager: memoryManager
        )
        self.memoryRecall = memoryRecall
        self.memoryCrystallizer = MemoryCrystallizer(
            gemma: gemma,
            manager: memoryManager,
            recallService: memoryRecall
        )
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
            skillRegistry: skillRegistry,
            memoryRecall: memoryRecall
        )
        self.digestGenerator = digestGenerator
        self.ingestionCoordinator = IngestionCoordinator(repo: knowledgeRepo)
        let downloader = ModelDownloader(gemma: gemma)
        self.modelDownloader = downloader
        self.benchmarkRunner = BenchmarkRunner(
            gemma: gemma,
            variant: downloader.selectedVariant
        )
        self.audioCaptureService = AudioCaptureService()
        self.visionCaptureService = VisionCaptureService()
        let musicSource = MusicSource()
        self.musicSource = musicSource
        let assembler = AmbientSnapshotAssembler(
            location: self.locationSource,
            motion: self.motionSource,
            music: musicSource,
            calendar: self.calendarSource,
            health: healthSource
        )
        self.ambientSnapshotAssembler = assembler
        // Give the RAG pipeline access to the assembler so every
        // chat turn gets a fresh "right now" block injected.
        self.ragPipeline.ambientAssembler = assembler
    }

    /// Async setup — called from `.task` on the root view.
    ///
    /// Order matters:
    /// 1. Load vector index from SwiftData
    /// 2. Load embedding model (if assets available)
    /// 3. If a model was previously downloaded, warm it up
    /// 4. Arm EgressGuard — all outbound traffic blocked from here on
    func bootstrap() async {
        // Log initial memory so we have a baseline before the model is
        // loaded. Jetsam kills are much easier to diagnose with a
        // timeline of RSS readings.
        MemoryProbe.snapshot(tag: "bootstrap.start")

        installMemoryWarningHandler()

        // Defensive audio-session reset. A previous crashed launch may
        // have left `AVAudioSession.setActive(true)` lingering in
        // CoreAudio's daemon state, which can crash the next mic
        // permission grant or audio-engine start. Deactivating here
        // is best-effort — the session may already be inactive.
        #if canImport(AVFAudio) && os(iOS) && !targetEnvironment(simulator)
        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            EidosLogger.shared.log(.info, category: .app,
                event: "audio-session.reset.ok")
        } catch {
            EidosLogger.shared.log(.debug, category: .app,
                event: "audio-session.reset.noop",
                message: error.localizedDescription)
        }
        #endif

        await knowledgeRepo.loadVectorStoreFromDB()
        try? await memoryManager.rebuildIndex()

        // Bootstrap the embedding-based memory recall index. Walks
        // every tier and embeds entries that aren't already in the
        // vector store. Deferred behind a Task.detached because:
        // (1) it depends on EmbeddingService.load() being warm, which
        //     happens lazily on first use,
        // (2) we don't want to block app open on it — chats work
        //     without recall, just less well, until the index lands.
        Task.detached { [weak self] in
            guard let self else { return }
            await self.memoryRecall.rebuildIndex()
        }

        // NLContextualEmbedding asset download fails in the iOS Simulator
        // (permission denied on `/var/db/com.apple.naturallanguaged`). On
        // device, Apple's CDN delivers the asset on first launch.
        //
        // On Mac Catalyst / Designed-for-iPad, the NL model adds
        // ~150 MB of resident memory. That's survivable, but every MB
        // counts when the user is running Gemma 4 E2B alongside. We
        // defer the embedding-model load until the first query that
        // actually needs embeddings (lazy init).
        #if !targetEnvironment(simulator)
        if await !embeddingService.hasAssets() {
            try? await embeddingService.ensureAssetsAvailable()
        }
        // Embedding model load deferred — see `EmbeddingService.load()`
        // is now called lazily by `KnowledgeRepository` on first use.
        #endif

        // External AltStore testers may update over a broken build, which
        // preserves UserDefaults and model folders. Clear that stale state
        // before the cached-model bootstrap path can bypass onboarding.
        modelDownloader.resetExternalTesterModelStateIfNeeded()

        MemoryProbe.snapshot(tag: "bootstrap.pre-model-load")

        // Load the cached model. If the files are missing or MLX rejects
        // them, clear the flag so onboarding/download shows again.
        if modelDownloader.isModelDownloaded {
            modelDownloader.beginCachedModelLoad()
            do {
                let selectedVariant = modelDownloader.selectedVariant
                try await gemma.load(
                    variant: selectedVariant,
                    config: ModelConfig(variant: selectedVariant)
                )
                modelDownloader.markModelReady()
            } catch {
                let msg = UserFacingError.message(for: error)
                modelDownloader.clearDownloadedModelState(message: msg)
                EidosLogger.shared.error(.model, event: "model.load.failed",
                    error: error, failure: .modelLoad)
            }
        }

        MemoryProbe.snapshot(tag: "bootstrap.post-model-load")

        // If the user has morning digest enabled, make sure it's scheduled.
        // Safe to call repeatedly — it removes+re-adds the pending request.
        if notificationScheduler.digestEnabled {
            await notificationScheduler.scheduleMorningDigest()
        }

        EgressGuard.install()

        // Activate ambient sources for anything the user has already
        // granted permission to. We never prompt here — that would be
        // invasive on launch. Permissions are requested in context
        // (the first time a feature needs them).
        //
        // Location: if "When in Use" or "Always" is already granted,
        // start significant-change monitoring so the morning briefing
        // has place context without further user action.
        if locationSource.authorizationStatus == .authorizedWhenInUse ||
           locationSource.authorizationStatus == .authorizedAlways {
            locationSource.startMonitoring()
            EidosLogger.shared.log(.info, category: .app, event: "location.auto-start")
        }

        // Register the background nudge task. iOS only — Mac Catalyst's
        // BGTaskScheduler is a no-op silently. After register, the task
        // is dormant; first scheduleNext() happens when the app
        // backgrounds. We schedule one immediately so iOS has a queued
        // request to consider on the very first background crossing.
        #if os(iOS) && !targetEnvironment(macCatalyst)
        NudgeBackgroundTask.register(
            proactive: proactiveDigestGenerator,
            notifications: notificationScheduler
        )
        NudgeBackgroundTask.scheduleNext()
        #endif

        isBootstrapped = true

        MemoryProbe.snapshot(tag: "bootstrap.done")
    }

    /// Hooks `UIApplication.didReceiveMemoryWarningNotification` so we
    /// log + react to pressure before the OS jetsams us.
    ///
    /// On Mac (Designed for iPad), iPhones with ≤6 GB RAM, or any device
    /// that has another memory-hungry app active at the same time, the
    /// combined Gemma-weights + KV-cache + UI footprint can push past
    /// the jetsam threshold. When a warning fires we:
    ///   1. Log the current RSS + thermal reading.
    ///   2. Auto-disable `longContextPackingEnabled` so the next RAG
    ///      turn uses the conservative 12 K-char budget. This is the
    ///      single biggest memory lever we control at runtime.
    ///   3. Tell the user in a follow-up log line.
    ///
    /// We do NOT auto-unload Gemma — it's too painful to reload and the
    /// warning rarely reflects a true crisis on modern devices.
    private func installMemoryWarningHandler() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MemoryProbe.snapshot(tag: "memory.warning")
                let flags = EidosFeatureFlags.shared
                if flags.longContextPackingEnabled {
                    flags.longContextPackingEnabled = false
                    EidosLogger.shared.log(
                        .warn, category: .model,
                        event: "memory.warning.auto-revert",
                        message: "Memory pressure — reverted to conservative context budget.",
                        failure: .modelOOM
                    )
                }
            }
        }
        #endif
    }
}
