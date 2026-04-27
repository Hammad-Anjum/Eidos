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

## Current state

**Done**:
- Phase 0 — Scaffolding (66 files, project.yml, all stubs compile against `AppContainer`)
- Phase 1 — Persistence + Embeddings + Repository (`NLContextualEmbedding`, `@ModelActor`, hybrid RRF search, content-hash dedup, real unit tests)

**Active**:
- Phase 2 planning is **complete and approved**. Ready for execution. First step: 2.0 (add `mlx-swift-examples` SPM dependency to `project.yml`, delete `Podfile`).

**Pending**:
- Phase 3 — RAG + single-pass chat with tools
- Phase 4 — iOS platform sources + skills (Calendar, Contacts, all 6 built-ins)
- Phase 5 — Share Extension + ingestion (WhatsApp + mbox importers)
- Phase 6 — Polish + tests (Settings, BG digest, app icon, full smoke suite)

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

---

## 2026-04-23 — Phase 8 begins: multimodal + observability

Gemma 4 was released 2026-04-02 with native text + image + audio + chain-of-thought support. The existing code path used `MLXLLM` (text-only). This session pivoted the plan to:

1. **Upgrade to `MLXVLM`** to unlock vision and audio (project.yml change + `GemmaSession` loader rewrite — scaffolded, swap pending).
2. **Ship developer-grade diagnostics** — `EidosLogger` (JSONL), `MetricsRecorder` (TTFT / tok/s / RSS / thermal), `FailureCategory` (25-case taxonomy), `BenchmarkRunner` + 11-category corpus, `DiagnosticsView` (Logs / Metrics / Benchmarks / Flags).
3. **Ship `SafetyGate`** — pre-LLM hardcoded refusal for self-harm / medical emergency / dosing / diagnosis / legal / child-safety. Always on in RELEASE. ~40 crisis-phrase unit tests.
4. **Lock Phase 9 design** (not yet implemented): 5 specialists + Master, master-dispatch routing, per-persona memory dirs, 3 notifications/day global budget, bundled public-domain knowledge corpora (USDA, MedlinePlus, WHO, OpenStax, ExerciseDB), paid skill packs as monetization.
5. **Codify engineering bar** — see `CLAUDE.md`: doc comments, typed errors, Swift 6 strict concurrency, no force-unwraps, crash-safe logging, machine-parseable metrics, fails-closed on safety, feature flags not branches.
6. **Designate `masterplan.md` as source of truth** — any design decision, new file, or pivot updates the plan in the same commit. `CLAUDE.md` enforces this for every future Claude session.
7. **Corpus strategy**: no runtime scraping (breaks EgressGuard). Bundle curated public-domain data at build time. Per-persona RAG > parametric knowledge for anything consequential.
8. **Confirmed existing conversation-history persistence**: `Conversation` + `ConversationMessage` SwiftData models (in `EmbeddingRecord.swift`) already persist every chat turn on-device, resume on launch, cascade-delete cleanly. Missing only a browse-past-conversations UI.

Full session record in [`conversations/2026-04-23_phase8_multimodal_observability.md`](conversations/2026-04-23_phase8_multimodal_observability.md).

---

## 2026-04-25 — Roadmap reframed around ambient agency

The user clarified the deeper product thesis: Eidos should not merely be a
private local AI app, but **another part of the phone** — one that requires
fewer commands over time, quietly prepares value in the background, and earns
trust through receipts and restraint.

That led to a strategic update to `masterplan.md`:

- Added a new product goal: **"Fades into the phone"**
- Added **Product Laws For Ambient Eidos** to govern future feature choices
- Added **Phase 9.5 — Ambient Agency + Trust Rails**
- Explicitly prioritized ambient agency over web search and hybrid-cloud work
- Defined the missing architectural pieces for this vision:
  `AuthorityProfile`, `ActionPolicyEngine`, `CommitmentLedger`,
  `PeopleGraph`, `RoutineGraph`, `PreparationEngine`, `SurfaceRouter`,
  `ReceiptCenter`, `SensitiveVault`, and a `BackgroundTriggerMatrix`

This was an important product-direction turning point: the moat is now stated
plainly as **continuity + initiative + receipts**, not "use a smarter model"
or "add cloud later."

---

## 2026-04-25 — Phase 8 closed

Phase 8 moved from "85% complete" to **complete for repo-owned work**.

The closeout batch did four things:

- Reached a green engineering baseline again: **174 / 174 simulator tests passing**
- Finished the practical multimodal path in the app: `MLXVLM` image input now runs end-to-end through chat and benchmark fixtures
- Tightened the safety / prompt / parser regression net, including a missed self-harm phrase (`"I wish I was dead"`)
- Restored the zero-warning bar on the repo side by migrating reverse geocoding to `MKReverseGeocodingRequest` and cleaning remaining prompt/test drift

The one honest caveat is now documented instead of left vague: **native raw
audio into Gemma is blocked by the current `mlx-swift-lm` public API surface**.
Eidos already has `AudioCaptureService` and `audio: Data?` plumbing in place,
but the package does not yet expose a raw audio attachment path alongside
images/videos. Shipping voice input therefore remains fully local via
`SpeechTranscriber` until upstream support lands.

---

## 2026-04-26 — First external AltStore test exposed E4B load crash

The first outside tester installed Eidos through AltStore and reached the
model-loading screen, then the app crashed while loading the selected model
into memory. Follow-up confirmed they had selected the larger **E4B** variant.

Decision:

- First external tester builds must force **E2B** until E2B has passed real
  iPhone loading and first-chat validation.
- E4B remains a DEBUG/dev-only path for now, not a Release tester option.
- `ModelDownloader.selectedVariant` now sanitizes any stale stored E4B choice
  back to E2B in Release builds.
- Regression tests now assert E2B is the first-run default.

This is not a product pivot; it is the device-first mandate applied correctly.
The local model is only useful if it survives first launch on a real phone.

Follow-up testing exposed a second startup bug: stale `eidos.modelDownloaded`
state could send the app straight to Home before MLX had actually loaded a
model. Startup now verifies required HuggingFace files on disk, shows explicit
download/loading/failure UI, and gates chat on `ModelDownloader.phase == .ready`
only. Test baseline moved to **192 / 192** passing, and a signed generic iOS
build succeeds after the hardening.

The next tester pass still skipped the download bar, proving the onboarding
`forceDownload` fix was too late in the launch sequence. Release tester builds
now force a one-time fresh model state before cached bootstrap runs and delete
old `gemma-e2b` / `gemma-e4b` folders before forced downloads. The verified
main-app-only AltStore artifact is
`build/Eidos-Tester-Pack-ForceFreshDownload-Release-MainOnly-v2.zip`; simulator
tests are **193 / 193** passing.

---

## Index of project documents

- [masterplan.md](masterplan.md) — **source of truth**. Phase plan, current state, design decisions. All feature changes reconcile here.
- [CLAUDE.md](CLAUDE.md) — working rules for any Claude Code session on this repo. Points at masterplan.
- [architecture.md](architecture.md) — canonical type/file/UI spec from the user. **Untouched** since project genesis. The "what we're building" reference.
- [plan.md](plan.md) — active build plan with Status, phase definitions, and Phase 2 detail. The "where we're going" reference.
- [notes.md](notes.md) — living research findings and design constraints. The "what we know is true" reference. Updated as we learn things.
- [history.md](history.md) — this file. The "why we got here" record. Appended at meaningful turning points.
- [conversations/](conversations/) — per-session Claude transcripts and decision records. One file per meaningful session.
- [SHORTCUTS.md](SHORTCUTS.md) — App Intent catalogue for the Shortcuts app.
- [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) — documented iOS-sandbox limits (not bugs).
- [README.md](README.md) — Mac handoff instructions and project layout.

---

## 2026-04-26/27 — Chat-stability marathon and architectural consolidation

A two-day push that compressed an entire Phase 8.1 into one external-tester loop. v3 through v12 shipped to AltStore over ~36 hours, each fixing a different undocumented landmine in the on-device Gemma 4 + iPhone 17 Pro Max stack: a `MainActor.assumeIsolated` trap in `DeviceProfile.formFactor` (v6), `MLX.Memory.clearCache()` discipline between every generation (v9), an `AVAudioSession` mode mismatch (v11), eight layered defenses against silent process kills (v12). Full record in `conversations/2026-04-26_chat_crash_marathon.md` with the dead-ends explicitly captured so future sessions don't repeat them.

Pushed the codebase to GitHub (`Hissam12/Eidos`) for the first time during this period, from a shared dev machine; documented the safe-credential workflow and teardown checklist in the dev log.

The 27th was a consolidation day: 5-domain architecture audit (`architecture_audit_2026-04-27.md`), Phase 8.2 mass-implementation sweep (10 ACTIONs landed: privacy snapshot overlay, biometric app lock, TLS hostname allowlist, structural prompt-injection defense, embedding-based memory recall service, `InferenceSession` protocol, background nudge scaffolding, regression tests), then a NEXT-1..10 wiring sweep that activated the dead code from Phase 8.2 and added curated tool calling, rolling token-budget history, memory pinning UI, conflict detection logging, decay-report visibility, onboarding privacy primer.

---

## 2026-04-27 — Retrieval architecture decided and SKG proposed

Ran a focused research pass on every flavor of retrieval architecture being talked about in 2026: GraphRAG (Microsoft), LightRAG (HKUST), PageIndex (Vectify), long-context Cache-Augmented Generation, Karpathy's April 2026 "LLM Wiki", embedding-model alternatives. Verdicts in `research_retrieval_2026-04-27.md`:

- All three KG-RAG variants (GraphRAG, LightRAG, PageIndex) infeasible on iPhone at single-user scale. LLM-pass indexing cost dominates. Skipped permanently.
- Long-context dump (128K context) fails past 16-32K tokens on iPhone before TPS becomes unbearable. Skipped as a primary retrieval path; usable only as fallback.
- Hybrid retrieval (BM25 via SQLite FTS5 + dense embeddings + Reciprocal Rank Fusion at k=60) is 2026 best practice for personal-scale on-device. Sub-millisecond. Built-into-iOS. Adopted as the retrieval backbone.
- Karpathy's "LLM Wiki" pattern (raw / wiki / CLAUDE.md, three operations: ingest / query / lint) directly validates Eidos's existing markdown-first design. Adopted.
- Embeddings: keep `NLContextualEmbedding` as default; pilot `EmbeddingGemma 308M` as opt-in upgrade behind a flag once we have a measured quality gap.
- Entities: YAML frontmatter tags + lazy SQLite `entity_mentions` index. No first-class knowledge graph; break-even doesn't exist for personal scale.

Same day, the user proposed and we validated a new memory architecture: **Self-Knowledge Graph (SKG)**. Zero-corpus cold start (no ingestion phase, ever — first-run UX is instant); user-centric topology (every node is an attribute or fact about the user, edges are mostly user→category→fact, dramatically simpler than a general-purpose KG); incremental classification at fact-write time using a 3-tier classifier (Apple `NLTagger` + keyword rules → `NLContextualEmbedding` cosine vs category centroids → Gemma fallback for uncertain cases, ~80% of facts hit the cheap path); decay-managed growth (existing `MemoryDecayEngine` operates on graph nodes, pruning the graph itself to bound size).

The combination of (1) on-device, (2) zero-corpus cold start, (3) decay-managed, (4) user-centric topology is genuinely novel — no shipping product hits all four. SKG implementation queued as `SKG-1` through `SKG-9` (~24 hours of focused work). Will replace per-tier markdown layout (`Memory/<tier>/<id>.md`) with per-category layout (`Memory/categories/<category>.md`) plus an opportunistic `entity_mentions` SQLite index. Decay engine and recall service survive unchanged.

Full SKG architectural argument and visual flowchart in `conversations/2026-04-27_phase82_and_skg.md`.
