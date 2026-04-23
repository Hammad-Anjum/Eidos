# Eidos — Project History

A chronological log of the major decisions, pivots, and milestones in the Eidos build. Companion to [architecture.md](architecture.md) (the canonical spec), [plan.md](plan.md) (active build plan), and [notes.md](notes.md) (research and constraints).

This file is the "why we got here" record. It does not get updated continuously — it's appended when meaningful turning points happen.

---

## 2026-04-12 — Project genesis

The user (working on Windows 10, with a macOS collaborator joining later) handed over a single file: a 1750-line `architecture.md` describing **SOMA**, a fully-local iOS personal AI assistant. The spec covered: Gemma on-device inference, CoreML MiniLM embeddings, SwiftData persistence, RAG retrieval, a skill/tool-calling layer, a Share Extension for cross-app ingestion, and importers for WhatsApp and mbox exports. The core promise was *zero data egress* — network used only for an initial model download.

The user asked me to plan and start building it, with two clarifications:
- Rename the project from **Soma** to **Eidos**
- Acknowledge that everything would be authored on Windows but compiled/validated on a Mac (initially via cloud-Mac handoff; later, a dedicated macOS collaborator)

---

## 2026-04-12 — Initial architectural review

A first pass through `architecture.md` flagged six issues: a fake hash tokenizer in `EmbeddingService` that would silently produce garbage embeddings, a `ContactsSource` permission bug, a `try!` regex in `IngestionCoordinator`, the App Group ID rename, missing skill stubs that `AppContainer` referenced, and the Gemma 4 model URLs being placeholders.

I initially asserted that "Gemma 4 doesn't exist" based on my knowledge cutoff (May 2025). The user corrected me: **Gemma 4 was released in early April 2026**, ~one week before this conversation. Lesson recorded in memory: do not assert the absence of post-cutoff developments — verify with web research first, and trust user corrections about current state.

---

## 2026-04-12 — Pivot to proactive architectural research

The user pushed back on a plan that only fixed obvious bugs. They asked for **significant architectural improvements** to be researched and surfaced proactively, not just minimum-ask compliance.

Web research turned up four architectural changes that materially reshaped the plan:

- **A1 — MediaPipeTasksGenAI is deprecated.** Google's documented successor was **LiteRT-LM**. The spec's entire inference dependency was wrong-by-default. *(This decision was revised again during Phase 2 — see below.)*
- **A2 — Gemma 4 supports native function calling.** The spec's two-pass skill-detection flow (one inference call to detect a tool, a second to generate the chat) was obsolete. The correct pattern is single-pass with constrained-decoding tool schemas in the prompt.
- **A3 — Apple ships `NLContextualEmbedding`.** iOS 17+ has a built-in BERT-based contextual embedding model running on the Neural Engine. This eliminated the entire MiniLM + WordPiece + CoreML + `convert_minilm.py` + `vocab.txt` pipeline from the spec. The embedding layer became a ~30-line wrapper.
- **A4 — `@Model` is not `Sendable`.** The spec's `Task.detached` + `@MainActor.run` background-embedding pattern wouldn't compile under Swift 6 strict concurrency. Apple's documented pattern is `@ModelActor` + `PersistentIdentifier` handoff. This required a new file.

Plus 15 smaller corrections (B1–B15): hybrid search, content-hash dedup, file protection, thermal guards, locale-aware importers, real MIME parsing, an auditable egress guard via `URLProtocol`, and a test target. All documented in `plan.md`.

---

## 2026-04-12 — Phase 0 (Scaffolding) executed

**Goal**: a fully-authored project tree the Mac collaborator could pick up via `xcodegen generate` and open in Xcode without surprises.

Output: **66 files** under [Eidos/](./), covering:
- Root config: [project.yml](project.yml) (XcodeGen), [Podfile](Podfile) (skeleton, deferred to Phase 2), [README.md](README.md), [.gitignore](.gitignore)
- Resources: [Info.plist](Eidos/Resources/Info.plist), [Eidos.entitlements](Eidos/Resources/Eidos.entitlements), [EidosShareExtension.entitlements](EidosShareExtension/EidosShareExtension.entitlements)
- App layer: [EidosApp.swift](Eidos/App/EidosApp.swift) (`@main`), [AppContainer.swift](Eidos/App/AppContainer.swift), [AppRouter.swift](Eidos/App/AppRouter.swift)
- Compilable stubs for every layer in `architecture.md` §3 (Inference, Embedding, KnowledgeBase, RAG, Skills, Platform, Ingestion, Digest, UI), all renamed Soma → Eidos, all wired into `AppContainer.init` so the dependency graph compiles from day one
- New files not in the spec: [KnowledgeBackgroundActor.swift](Eidos/KnowledgeBase/KnowledgeBackgroundActor.swift) (A4), [EgressGuard.swift](Eidos/Platform/EgressGuard.swift) (B14)
- [EidosTests/](EidosTests/) target with seeded test files
- Architectural decisions baked in from day one: `.completeFileProtection` (B6), `contentHash` field on `KnowledgeEntry` (B8), App Group `group.com.eidos.shared` (B4), `B2` `ContactsSource` fix, `B3` regex fix

Verified zero `Soma`/`com.soma` references in authored code (only the untouched `architecture.md` and `plan.md` retain the rename history).

**Project decision recorded**: chose **XcodeGen** over hand-authored `.xcodeproj` files. YAML is reviewable, hand-authored `pbxproj` is fragile from a non-Mac host.

---

## 2026-04-12 — Phase 1 (Persistence + Embeddings + Repository) executed

**Goal**: the entire knowledge-base pipeline authored in its real form, Swift-6-clean, ready for the Mac collaborator to compile and test.

Research first, code second. WebSearch confirmed:
- `NLContextualEmbedding` API surface: `hasAvailableAssets`, `requestEmbeddingAssets() async throws`, `load() throws`, `embeddingResult(for:language:)`, per-token vectors via `enumerateTokenVectors(in:using:)` callback yielding `[Double]`. Dimension is runtime-only via `embedding.dimension`.
- `@ModelActor` macro synthesises `init(modelContainer:)`, `nonisolated let modelContainer`, `let modelContext`, and a `subscript<T>(id: PersistentIdentifier, as: T.Type) -> T?`.

**Files moved from stub → real**:
- [Eidos/Embedding/EmbeddingService.swift](Eidos/Embedding/EmbeddingService.swift) — full rewrite. `NLContextualEmbedding` wrapper with `hasAssets` / `ensureAssetsAvailable` / `load` / `embed`. Mean-pools per-token vectors via Accelerate `vDSP`, then L2-normalises so a dot product in `VectorStore` gives cosine similarity.
- [Eidos/KnowledgeBase/KnowledgeBackgroundActor.swift](Eidos/KnowledgeBase/KnowledgeBackgroundActor.swift) — `@ModelActor` implementation. Takes a `PersistentIdentifier`, re-fetches the entry locally, chunks → embeds → writes `EmbeddingRecord`s through its own `modelContext`. Thermal guard between chunks (B11). `@Model` objects never cross actor boundaries.
- [Eidos/KnowledgeBase/KnowledgeRepository.swift](Eidos/KnowledgeBase/KnowledgeRepository.swift) — `insert` with content-hash dedup (B8) and `Task.detached` handoff to the background actor. `search` with hybrid vector + keyword via Reciprocal Rank Fusion (B9, `k=60`). Snippet extractor for search-result UI.
- [Eidos/App/AppContainer.swift](Eidos/App/AppContainer.swift) — constructs `KnowledgeBackgroundActor` once, injects into `KnowledgeRepository`. `bootstrap()` orders the asset preinstall → embedding load → model load → `EgressGuard.install()` sequence (§A3-asset).
- [Eidos/App/EidosApp.swift](Eidos/App/EidosApp.swift) — removed early `EgressGuard.install()` from `init` (now happens inside `bootstrap()`).

**Tests written**: real coverage for `TextChunker` (overlap, equality boundary, full reconstruction), `VectorStore` (orthogonal-axis ordering, near-vs-far ranking, removal), `KnowledgeRepository.reciprocalRankFusion` (empty, single-list, two-list, "two mediocre lists beat one excellent" property, deterministic tiebreaker).

**§A3-asset decision**: `NLContextualEmbedding.requestEmbeddingAssets()` downloads from Apple's CDN on first launch — a second network exception beyond the Gemma model download. Resolved by running asset preinstall in `AppContainer.bootstrap()` **before** `EgressGuard.install()` arms the allowlist. Documented in `plan.md` as A3-asset.

---

## 2026-04-12 — Reframing: drop the Windows constraint

The user announced that a macOS collaborator would work alongside Windows authoring, in real time. This eliminated the "Windows authoring → Mac validation gate" framing that had structured the original phased plan.

Plan implications:
- Verification stops being "hand-review on Windows then compile on Mac later" and becomes "real `xcodebuild test` runs as soon as code lands."
- Phases can be sequenced by feature completeness instead of authoring location.
- The "First Mac Session" framing in the original Phase 2 disappears — Mac sessions are continuous.

This was a documentation refactor, not a code change. The Phase 0 and Phase 1 outputs were unaffected.

---

## 2026-04-12 — Phase 2 planning, MLX pivot

Phase 2 was originally going to be the LiteRT-LM bring-up. Research turned up a hard blocker:

> **LiteRT-LM v0.10.1** (current latest, April 2026) ships stable APIs only for **Kotlin, Python, and C++**. Swift status is **🚀 In Dev** — explicitly noted in the README's supported-language table. No release date.

Plan §A1 was technically correct (replace deprecated MediaPipeTasksGenAI with LiteRT-LM), but **not actionable**. Pivoted to **MLX Swift** (`github.com/ml-explore/mlx-swift` + `mlx-swift-examples`):
- Apple's first-party on-device ML framework
- Stable Swift API today, SPM distribution
- Reference iOS apps shipped by Apple's ML team (`LLMBasic`, `LLMEval`, `MLXChatExample`)
- Token-by-token streaming via `AsyncThrowingStream` — exactly the API shape Phase 0 had already designed
- Models loaded by Hugging Face ID (`mlx-community/gemma-4-E2B-it-4bit`)
- Apple-blessed via the swift.org blog post "On-device ML research with MLX and Swift"

Plan §A1 was revised to document the MediaPipeTasksGenAI → LiteRT-LM → MLX path. The `Podfile` will be deleted in Phase 2.0 (MLX is SPM-only).

A second research finding became a design constraint:

> **iPhone 13 base** has 4 GB RAM with **~2.2 GB usable per app**. Gemma 4 E4B at ~3 GB on disk **cannot fit in memory** on iPhone 13 base. Only iPhone 13 Pro and later (6 GB+) can run E4B.

`GemmaVariant` will need a `requiresDeviceClass` field, and the onboarding UI will hide E4B on 4 GB devices. Documented in `notes.md` Design Constraints.

**User decisions baked into Phase 2** (replied during planning):
1. **Default variant: E2B**, with explicit "upgrade to E4B" path in Settings (gated on device class).
2. **Function-calling template plumbed in Phase 2**, even though Phase 3 wires it to skills.
3. **`ChatView` empty state copy**: "Model not installed — download in Settings." Concrete, not euphemistic.
4. **Model storage**: `~/Library/Application Support/Models/` — invisible to the Files app.
5. **Async warmup**: model load runs in `AppContainer.bootstrap()` after onboarding; `ChatView` shows "warming up..." until ready.

---

## 2026-04-12 — Documentation split: plan + notes + history

The user asked for research findings and design constraints to live in their own MD file alongside `architecture.md` and `plan.md`, so the build plan stays focused on "what we're going to do" and the notes stay focused on "what we know is true."

Created:
- [notes.md](notes.md) — living research/constraints doc with three sections: **Latest Updates**, **Implementation Research** (MLX surface, NLContextualEmbedding, `@ModelActor`, Gemma 4 chat template), **Design Constraints** (memory budget table, privacy rules, concurrency rules, build/storage targets, testing policy)
- [history.md](history.md) — this file

Updated [plan.md](plan.md) to mirror the approved Phase 2 plan: dropped the Windows-only framing, revised §A1 to document the MLX pivot, added a Status section, added the full Phase 2 active section with sub-phases 2.0–2.8 and a file-impact table.

---

## 2026-04-12 → 2026-04-23 — Mac-side sprint: phases 2–7 scoped

After Phase 2 planning was approved, the macOS co-founder (Hissamuddin) ran an eleven-day sprint that shipped a scoped version of the remaining roadmap. The Windows side continued as reference only; the Mac side became authoritative. This entry summarises what landed.

### Phase 2 — Inference (MLX Swift + Gemma 4)

- Swapped the planned `mlx-swift-examples` dependency for the more focused `mlx-swift-lm` package, plus `huggingface/swift-transformers` and `huggingface/swift-huggingface`. Three SPM packages, no CocoaPods.
- `HuggingFaceDownloader.swift` replaced the `ModelDownloader` stub. Uses `swift-huggingface` directly instead of wrapping MLX's Hub snapshot API.
- `GemmaSession` wired up against `MLXLLM` / `MLXLMCommon` / `MLXHuggingFace`. Streaming via `AsyncThrowingStream` as designed.
- `Eidos.xcodeproj` now generates cleanly from `project.yml` (191 lines, 5 targets).
- Bundle ID convention settled: `com.hissamuddin.eidos` (not the placeholder `com.eidos.app`). App Group: `group.com.hissamuddin.eidos`.
- Real-device validation still pending per README.

### Phase 3 — Memory system + RAG + voice + KB

- Introduced a **new `Memory/` layer** not in the original spec: eight files implementing a tiered priority-based memory store (P1–P5: core_identity, active, topic, recent, archive). Markdown files on disk as the source of truth.
  - `MemoryEntry`, `MemoryManager`, `MemoryIndex` — model + coordinator + index
  - `MemoryDecayEngine` — automatic priority decay so old memories fade
  - `MemoryCrystallizer` — end-of-session consolidation (summarises recent context into longer-lived entries)
  - `KnowledgeAggregator` — unifies KB entries and memory entries for retrieval
  - `MemoryExporter` — zips memory directory for Files-app export
  - `MemoryFrontmatter` — YAML frontmatter parsing/writing for the Markdown files
- `RAGPipeline` + `ContextBuilder` implemented around the hybrid RRF search from Phase 1, now pulling from both `KnowledgeRepository` and `MemoryManager`.
- `SpeechTranscriber` wired into chat bar with `requiresOnDeviceRecognition = true`.
- Full KB browser UI: `KBBrowserView`, `KBEntryDetailView` with edit/delete.
- Full Memory browser UI under `Eidos/UI/Memory/`.

### Phase 4 — Platform sources + skills + home/digest

Platform layer expanded from 5 files to 14. New sources:
- `HealthSource` — optional HealthKit read (sleep, steps, heart rate, active energy). Insights only, never raw samples.
- `LocationSource` — significant-change only, never tracks path.
- `MotionSource` — activity + step count for briefing context.
- `MusicSource` — recently-played for ambient briefing colour.
- `FocusObserver` — respects Focus modes.
- `NotificationScheduler` — daily briefing at a configurable time.
- `LiveActivityManager` — coordinates the Live Activity lifecycle.
- `AppAction` + `AppActionRegistry` — registry of user-confirmed outbound actions.

Skills expanded from 6 to **13**:
- Core: `CalendarSkill` (read/write), `RemindersSkill` (read/create), `ContactsSkill`, `SearchKBSkill`, `AddNoteSkill`, `DigestSkill`.
- App Actions (`AppActionSkills.swift`): WhatsApp, SMS, Email, Call, Navigate, Ride. Every app action goes through an `ActionConfirmationSheet` before dispatch — no silent sends.

Home + Digest: `HomeView` shows the morning briefing; `DigestGenerator` plus `ProactiveDigestGenerator` weave calendar, reminders, memory highlights, and HealthKit insights.

### Phase 5 — App actions + importers

- `AppIntents/` added (`EidosAppShortcuts.swift`, `EidosIntents.swift`) — Apple Shortcuts integration so users can trigger Eidos from Siri / voice / Shortcuts app.
- Importer trio stayed: `WhatsAppImporter`, `MailImporter`, `PlainTextImporter`, plus `IngestionCoordinator`.
- `EidosShareExtension` scaffold is in place; real implementation deferred to Phase 6.x per `masterplan.md`.

### Phase 6 — Proactive intelligence + HealthKit + notifications

- `ProactiveDigestGenerator` for briefings composed from multiple sources.
- Live Activity widget (`EidosWidget` target) shows the daily digest on the lock screen / Dynamic Island.
- `NotificationScheduler` drives the daily briefing local notification.
- `FeatureTourView` — first-run orientation overlay.
- Per `masterplan.md`, three sub-phases deferred: 6.1 routine learner, 6.4 life log, 6.5 tone engine.

### Phase 7 — Polish + tests

**Test coverage**: 13 new test files, 120+ tests total passing:
- `AppActionTests`, `ContextBuilderTests`, `EgressGuardTests`, `HealthInsightTests`, `ImporterTests`
- `MemoryCrystallizerTests`, `MemoryDecayEngineTests`, `MemoryIndexTests`, `MemoryManagerTests`
- `NotificationSchedulerTests`, `PromptTemplatesTests`, `RAGIntegrationTests`, `SkillsTests`
- Plus the existing `RRFusionTests`, `TextChunkerTests`, `VectorStoreTests` from Phase 1.

**UI polish**: `AIGlowBorder` component, `UserFacingError` type for consistent error surfaces, refined onboarding and settings.

### New targets

- `EidosShared/` — code shared between the app and the widget (`SharedStore.swift`, `DigestActivityAttributes.swift`, `WidgetDigestSnapshot.swift`).
- `EidosWidget/` — widget extension: `DigestLiveActivity.swift`, `DigestWidget.swift`, `DigestWidgetView.swift`, `EidosControls.swift`, `EidosWidgetBundle.swift`.

### New project docs

- `masterplan.md` — consolidated strategic roadmap, supersedes the day-to-day role of `plan.md`.
- `KNOWN_LIMITATIONS.md` — honest accounting of gaps (e.g. `EgressGuard`'s scope only covers `URLSession.shared`, not custom-configured sessions).
- `SHORTCUTS.md` — user documentation for the AppIntents / Shortcuts surface.

### Removed

- `Podfile` — MLX is SPM-only, planned deletion executed.

### Sync operation (2026-04-23)

The macOS work arrived as `Eidos-main.zip` (unpacked to `Eidos-main/` alongside `__MACOSX/`). The sync was a wholesale replacement:

1. Deleted stale Windows-side `Podfile`, `Eidos/`, `EidosShareExtension/`, `EidosTests/` at the repo root.
2. Copied `Eidos-main/.` contents to the repo root (including hidden `.gitignore`).
3. Removed `Eidos-main/` and `__MACOSX/` staging directories.
4. Verified `Eidos.xcodeproj/` is gitignored (matched by `*.xcodeproj`).

Final `git status`: 1 deletion (`Podfile`), ~48 modifications, ~35 new untracked paths (new folders like `EidosShared/`, `EidosWidget/`, `Eidos/Memory/`, `Eidos/App/AppIntents/`, `Eidos/UI/Memory/`, plus the new Platform / Skill / UI / Test files and the three new root docs).

---

## Current state

**Done** (scoped form, per `masterplan.md`):
- Phase 0 — Scaffolding
- Phase 1 — Persistence + embeddings + hybrid RRF
- Phase 2 — Inference (MLX Swift + Gemma 4). Real-device validation pending.
- Phase 3 — Memory system + RAG + voice + KB browser
- Phase 4 — Platform sources + 13 skills + home/digest (4.3 relationship intel, 4.4 notifications deferred to 6.x)
- Phase 5 — App actions + importers (5.2 real share-ext implementation, 5.4 richer App Intents deferred)
- Phase 6 — Proactive intelligence + HealthKit + notifications (6.1 routine learner, 6.4 life log, 6.5 tone engine deferred)
- Phase 7 — Polish + tests + ship-readiness (120+ tests passing)

**Active**:
- Real-device validation on iPhone 13+ (the one thing the Simulator can't verify — MLX Metal shaders don't run there).
- Deferred features flagged in `masterplan.md` for pickup as "phase 6.x" follow-ups.

---

## Pivots and corrections

A condensed list of every direction change in the project so far. Each entry is "the original plan" → "the new plan" with a one-line reason.

1. **Project name**: Soma → Eidos. *(User preference.)*
2. **Inference SDK**: MediaPipeTasksGenAI (spec) → LiteRT-LM (research) → **MLX Swift** (research, current). *(MediaPipe deprecated; LiteRT-LM Swift API not yet released; MLX is Apple-first-party with stable Swift bindings.)*
3. **Embeddings**: bundled MiniLM + CoreML + WordPiece + `convert_minilm.py` (spec) → **`NLContextualEmbedding`** (Apple built-in). *(Eliminates ~120 lines of boilerplate, the broken hash tokenizer, and a 90 MB bundled asset.)*
4. **Function calling**: two-pass skill detection (spec) → **single-pass with native Gemma 4 function calling** in the prompt. *(Halves per-message inference cost.)*
5. **Background embedding**: `Task.detached` + `@MainActor.run` (spec) → **`@ModelActor`** + `PersistentIdentifier` handoff. *(Spec pattern doesn't compile under Swift 6 — `@Model` isn't `Sendable`.)*
6. **EgressGuard install timing**: in `EidosApp.init` (Phase 0) → in `AppContainer.bootstrap()` after asset preinstall (Phase 1, §A3-asset). *(Otherwise the first-launch `NLContextualEmbedding` asset fetch from Apple's CDN gets blocked by our own guard.)*
7. **Project file authoring**: hand-edit `.xcodeproj` (impossible from Windows) → **XcodeGen `project.yml`**. *(YAML is reviewable; pbxproj is fragile.)*
8. **Dependency manager**: CocoaPods (spec) → **SPM only**. *(MLX is SPM-only. `Podfile` will be deleted in Phase 2.0.)*
9. **Phase sequencing**: "Windows authoring → Mac handoff gate" → **continuous Windows + Mac collaboration**. *(User added a macOS collaborator working alongside.)*
10. **Default model variant**: E4B (spec) → **E2B** with device-gated E4B upgrade. *(Memory budget research: iPhone 13 base can't fit E4B.)*
11. **Search**: keyword fallback when embeddings unavailable (spec) → **hybrid vector + keyword via RRF**, always. *(Catches exact-match queries that semantic search underweights.)*
12. **Chat empty state**: "warming up..." (initial draft) → **"Model not installed — download in Settings."** *(User feedback: don't mislead users about whether download is necessary.)*
13. **Model storage location**: `~/Documents/Models/` (spec) → **`~/Library/Application Support/Models/`**. *(Invisible to Files app; same on-device guarantees.)*
14. **Model warmup**: sync in onboarding (initial draft) → **async in bootstrap, with `ChatView` loading state**. *(More forgiving UX.)*
15. **MLX package**: `mlx-swift-examples` (Phase 2 plan) → **`mlx-swift-lm`** (Mac sprint). *(More focused surface, same ecosystem.)*
16. **Model download stack**: custom `ModelDownloader` wrapping MLX Hub (plan) → **`HuggingFaceDownloader`** using `swift-huggingface` directly. *(Fewer abstractions.)*
17. **Bundle ID / App Group**: `com.eidos.app` / `group.com.eidos.shared` (placeholder) → **`com.hissamuddin.eidos` / `group.com.hissamuddin.eidos`**. *(Personal developer team convention.)*
18. **Skills count**: 6 built-in (plan) → **13 built-in** (Mac sprint). Added App Actions: WhatsApp, SMS, Email, Call, Navigate, Ride — all gated behind `ActionConfirmationSheet`. *(Agentic scope expanded.)*
19. **Memory model**: flat KB only (plan) → **tiered priority memory (P1–P5) alongside the KB**. Markdown-on-disk store with automatic decay and end-of-session crystallisation. *(Richer long-term behaviour.)*
20. **Widget / Live Activity**: not in plan → **`EidosWidget` target with Live Activity for the daily briefing**. *(Lock-screen presence.)*
21. **Apple Shortcuts**: not in plan → **`AppIntents` integration** for voice / Siri / Shortcuts app triggers. *(Hands-free access surface.)*
22. **HealthKit**: not in plan → **optional health read** (sleep, steps, heart rate, active energy). Insights only, raw samples never persisted. *(Briefing personalisation.)*
23. **Primary plan doc**: `plan.md` → **`masterplan.md`**. *(Running roadmap document managed by the Mac side; `plan.md` remains as historical reference.)*

---

## Index of project documents

Four reference docs, plus user-facing surface docs:

- [architecture.md](architecture.md) — canonical type/file/UI spec from the user. **Untouched** since project genesis. The "what we're building" reference.
- [masterplan.md](masterplan.md) — **active strategic roadmap** (Mac-side). Primary build plan going forward. Supersedes `plan.md` as the day-to-day reference.
- [plan.md](plan.md) — earlier build plan covering phases 0–2. Retained for historical context; see `masterplan.md` for current direction.
- [notes.md](notes.md) — living research findings and design constraints. The "what we know is true" reference. Updated as we learn things.
- [research.md](research.md) — exploratory architectural deep-dives being evaluated (OpenClaw-style agent loop, PageIndex / vectorless RAG).
- [history.md](history.md) — this file. The "why we got here" record. Appended at meaningful turning points.
- [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) — honest accounting of known gaps and deferred work.
- [SHORTCUTS.md](SHORTCUTS.md) — user documentation for the Apple Shortcuts / AppIntents surface.
- [README.md](README.md) — build instructions, requirements, project layout.
