import Foundation
import SwiftData
import MLX
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFAudio)
import AVFAudio
#endif

/// Dependency-injection root for Eidos AuADHD companion.
///
/// Pivoted from medical-helper to AuADHD (2026-05-12). Existing
/// cleanup carried over from the medical-helper branch (digest,
/// ingestion, Motion / Music sources, LiveActivityManager,
/// AppActionRegistry, communication skills already gone).
///
/// Next session lands four AuADHD-shaped tools against the
/// `SkillRegistry`:
///   - `BreakDownSceneSkill` (vision → spoken 3-step plan)
///   - `VoiceJournalCaptureSkill` (mic → crystallized journal entries)
///   - `RecallRelevantMemoriesSkill` (chat tool, embedding search)
///   - `PickNextTaskSkill` (calendar + memory + energy → 1 task)
///
/// Kept: Gemma + MLX, embedding + vector substrate, knowledge repository,
/// memory system + decay + crystallizer + recall, RAG pipeline, Calendar
/// / Contacts / Health / Location sources, vision + audio + speech
/// capture, notification scheduler, model downloader, benchmark runner.
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
    let modelDownloader: ModelDownloader
    let memoryManager: MemoryManager
    /// Embedding-based semantic recall over the memory store. Bridges
    /// EmbeddingService + VectorStore + MemoryManager so chat turns can
    /// find memories by meaning, not just keyword. After this is
    /// constructed, every newly-crystallized memory is auto-indexed.
    let memoryRecall: MemoryRecallService
    let memoryDecayEngine: MemoryDecayEngine
    let memoryCrystallizer: MemoryCrystallizer
    let healthSource: HealthSource
    let notificationScheduler: NotificationScheduler
    let locationSource: LocationSource
    let benchmarkRunner: BenchmarkRunner
    let audioCaptureService: AudioCaptureService
    let visionCaptureService: VisionCaptureService
    let ambientSnapshotAssembler: AmbientSnapshotAssembler
    var isBootstrapped = false

    /// One-shot chat launch intent. Home tiles set this when the user
    /// taps Look / Ground / What Now; `ChatView` consumes it on the
    /// next render and clears it. See `ChatLaunchIntent` for fields.
    var pendingChatLaunch: ChatLaunchIntent?

    init() throws {
        let schema = Schema([
            KnowledgeEntry.self,
            EmbeddingRecord.self,
            Conversation.self,
            ConversationMessage.self,
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

        // Build `memoryRecall` here (rather than lower in this init)
        // so we can pass it to `RecallRelevantMemoriesSkill`. The
        // service is cheap to construct — the vector index is
        // populated lazily on first use.
        let memoryRecall = MemoryRecallService(
            embedding: embeddingService,
            vectorStore: vectorStore,
            manager: memoryManager
        )

        // AuADHD skills (Phase 2, 2026-05-12). The system prompt's
        // AuADHD addendum (in `PromptTemplates.systemPrompt`)
        // instructs Gemma when to call each:
        //   - `break_down_scene` — when a photo of a cluttered scene
        //     is attached + the user signals overwhelm.
        //   - `pick_next_task` — when the user signals decision
        //     fatigue ("what now", "brain stopped").
        //   - `voice_journal_capture` — bypass-the-chat path, called
        //     imperatively from the Home Journal tile (not by Gemma
        //     in the loop). Registered here for completeness.
        //   - `recall_relevant_memories` — when the user references
        //     something they "told you before."
        //   - `start_body_double` — the AuADHD differentiator. Bypass-
        //     the-chat path, dispatched imperatively from `BodyDoublingView`
        //     when the user taps the "Sit With Me" tile. Writes a
        //     session memory entry and returns the canonical opening
        //     line; the view owns the timer + halfway / closing cues.
        // Order matters: `chatLite`'s curated-tools path exposes the top
        // 3 from `SkillRegistry.availableSkills().prefix(3)` (the cap
        // keeps prompt prefill cheap on iPhone). Chat-path tools come
        // FIRST so they land in that cap; imperative-only tools
        // (dispatched directly from views — JournalRecordingView /
        // BodyDoublingView — and never selected by Gemma in chat) come
        // after. Without this ordering, RecallRelevantMemoriesSkill was
        // demoted out of the cap, breaking the hero ramble->recall flow
        // whenever Gemma chose to emit a tool call for it.
        let skills: [any Skill] = [
            // Chat-path tools (exposed in chatLite curated catalogue):
            BreakDownSceneSkill(memory: memoryManager),
            PickNextTaskSkill(memory: memoryManager, calendar: calendarSource),
            RecallRelevantMemoriesSkill(recall: memoryRecall),
            // Imperative-only (dispatched from views, never via Gemma):
            VoiceJournalCaptureSkill(memory: memoryManager),
            BodyDoubleSkill(memory: memoryManager),
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
        // `memoryRecall` was constructed above so it could be passed
        // into `RecallRelevantMemoriesSkill`. Just assign it here.
        self.memoryRecall = memoryRecall
        self.memoryCrystallizer = MemoryCrystallizer(
            gemma: gemma,
            manager: memoryManager,
            recallService: memoryRecall
        )
        let healthSource = HealthSource()
        self.healthSource = healthSource
        self.notificationScheduler = NotificationScheduler()
        self.locationSource = LocationSource()
        self.ragPipeline = RAGPipeline(
            gemma: gemma,
            knowledgeRepo: knowledgeRepo,
            memoryManager: memoryManager,
            skillRegistry: skillRegistry,
            memoryRecall: memoryRecall
        )
        let downloader = ModelDownloader(gemma: gemma)
        self.modelDownloader = downloader
        self.benchmarkRunner = BenchmarkRunner(
            gemma: gemma,
            variant: downloader.selectedVariant
        )
        self.audioCaptureService = AudioCaptureService()
        self.visionCaptureService = VisionCaptureService()
        let assembler = AmbientSnapshotAssembler(
            location: self.locationSource,
            calendar: self.calendarSource,
            health: healthSource
        )
        self.ambientSnapshotAssembler = assembler
        // Give the RAG pipeline access to the assembler so every chat
        // turn can pull a fresh "right now" block when needed.
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

        // Post-save hook: every successful `MemoryManager.save(...)`
        // re-embeds the entry into the recall index. Without this, a
        // freshly-saved memory (e.g. a voice journal recorded seconds
        // ago) is invisible to semantic recall until the next app
        // launch's `rebuildIndex()` — which breaks the demo's hero
        // flow ("ramble into journal, immediately ask 'what did I say
        // about Maya?'"). Mirrors the `MemoryCrystallizer.attachRecallService`
        // pattern: avoids a circular type dep that would otherwise
        // form if MemoryManager imported MemoryRecallService directly.
        await memoryManager.attachOnSave { [memoryRecall] entry in
            await memoryRecall.indexEntry(entry)
        }

        // DEMO-MODE MEMORY CUT (2026-05-19): the embedding service
        // load + index rebuild at bootstrap was pushing iPhone past
        // the foreground-app RAM ceiling alongside Gemma's 3.58 GB
        // weights — `app.memory-warning` fired twice during bootstrap,
        // then Metal kernel JIT during first generation pushed it over
        // and the process was SIGKILL'd before stream.first-token.
        //
        // The cut: skip `embeddingService.load()` and skip the eager
        // `rebuildIndex()`. Semantic recall silently falls back to
        // rule-based recall (P1 + activePriorities + topK hot topic
        // by recency from ContextBuilder). Saves ~50 MB at bootstrap
        // and removes the 8 indexing operations that allocated
        // temporary buffers during the most memory-pressured window
        // of app launch. Trade-off: "journal → immediate recall"
        // hero demo flow becomes rule-based, not semantic — recall
        // can still surface recent memories by recency / tier, just
        // not by topical similarity.
        //
        // Asset download via `ensureAssetsAvailable()` is kept (cheap,
        // doesn't load the model into memory; just downloads ~50 MB to
        // disk for future launches). Must still run before
        // `EgressGuard.install()` since it hits Apple's CDN.
        //
        // NLContextualEmbedding asset download fails in the iOS Simulator
        // (permission denied on `/var/db/com.apple.naturallanguaged`).
        #if !targetEnvironment(simulator)
        if await !embeddingService.hasAssets() {
            try? await embeddingService.ensureAssetsAvailable()
        }
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
                // DEMO-MODE MEMORY CUT (2026-05-19): drop any
                // transient Metal buffers MLX reserved during the
                // model-load tensor unpack. Gemma 4 E2B's weight load
                // leaves a non-trivial residual heap that piles on
                // top of the 3.58 GB model weights, leaving the
                // foreground app close to its iPhone RAM ceiling
                // before chat even starts. clearCache here just
                // releases the unpack scratch, not the weights.
                #if !targetEnvironment(simulator)
                MLX.Memory.clearCache()
                #endif
            } catch {
                let msg = UserFacingError.message(for: error)
                modelDownloader.clearDownloadedModelState(message: msg)
                EidosLogger.shared.error(.model, event: "model.load.failed",
                    error: error, failure: .modelLoad)
            }
        }

        MemoryProbe.snapshot(tag: "bootstrap.post-model-load")

        EgressGuard.install()

        // Activate ambient sources for anything the user has already
        // granted permission to. Location stays kept for v2 ambient
        // signal — AuADHD v1 doesn't fire on arrived-home triggers.
        if locationSource.authorizationStatus == .authorizedWhenInUse ||
           locationSource.authorizationStatus == .authorizedAlways {
            locationSource.startMonitoring()
            EidosLogger.shared.log(.info, category: .app, event: "location.auto-start")
        }

        // Demo-time data fixture. Only fires in DEBUG, only when the
        // activePriorities tier is empty — never overwrites real user
        // data. Gives the "What Now" flow a realistic spread of tasks
        // so the picker has something to land on during the hackathon
        // demo shoot.
        #if DEBUG
        await seedDemoActivePrioritiesIfEmpty()
        #endif

        isBootstrapped = true

        MemoryProbe.snapshot(tag: "bootstrap.done")
    }

    #if DEBUG
    /// Seeds five canonical activePriorities entries the first time the
    /// app launches on a clean install. Idempotent — re-runs see an
    /// already-populated tier and bail. The entries are written through
    /// `MemoryManager.save(_:)` so the `onSave` recall hook fires and
    /// they become semantically findable on the same launch.
    private func seedDemoActivePrioritiesIfEmpty() async {
        let existing = await memoryManager.index.records(tier: .activePriorities)
        guard existing.isEmpty else { return }

        let fixtures: [(title: String, body: String, priority: MemoryPriority)] = [
            ("Email Maya re: Q3 timeline pushback",
             "Reply to Maya's thread about the Q3 slip. Two paragraphs max — name the date, name the unblocker.",
             .p2),
            ("Schedule annual physical",
             "Find the GP's number, book the next open slot. Insurance card is in the wallet.",
             .p2),
            ("Move laundry to dryer",
             "Wet load has been in the washer since this morning.",
             .p3),
            ("Reply to Dad about Sunday",
             "Sunday lunch — yes/no. He texted Thursday.",
             .p3),
            ("Buy birthday card for Sam",
             "Sam's birthday is in 9 days. Card + small note.",
             .p3),
        ]

        for fixture in fixtures {
            let entry = MemoryEntry(
                tier: .activePriorities,
                title: fixture.title,
                body: fixture.body,
                priority: fixture.priority,
                tags: ["demo-seed"]
            )
            do {
                // `reindex: false` skips the onSave hook because the
                // recall index is bootstrapped on a Task.detached path
                // and may not have loaded the NLContextualEmbedding
                // assets yet by the time bootstrap reaches the seed.
                // Without this, every seeded entry logs
                // `memory.recall.index-failed — Embedding service is
                // not loaded` (5× per launch). Seeded priorities don't
                // need semantic recall: they're surfaced by the
                // `PickNextTaskSkill` rule-based path and by the
                // Memory tab's tier-grouped browser. Real user-created
                // entries (journals, scene breakdowns) still index
                // normally via the hook.
                _ = try await memoryManager.save(entry, reindex: false)
            } catch {
                EidosLogger.shared.error(
                    .memory,
                    event: "bootstrap.demo-seed.failed",
                    error: error,
                    failure: .memoryWrite,
                    extra: ["title": fixture.title]
                )
            }
        }
        EidosLogger.shared.log(
            .info, category: .memory,
            event: "bootstrap.demo-seed.ok",
            payload: ["count": fixtures.count]
        )
    }
    #endif

    /// Hooks `UIApplication.didReceiveMemoryWarningNotification` so we
    /// log + react to pressure before the OS jetsams us.
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
