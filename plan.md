# Eidos — Build Plan

## Context

**Eidos** (formerly "Soma" in the architecture doc) is a fully-local iOS personal AI assistant: Gemma 4 on-device via **MLX Swift**, Apple `NLContextualEmbedding` for on-device embeddings, SwiftData persistence, RAG retrieval, a skills/tool-calling layer, a Share Extension for cross-app ingestion, and importers for WhatsApp and mbox exports. The core promise is **zero data egress** — network is used exactly once, for the initial model download.

The full design lives in [architecture.md](architecture.md) (1750 lines, extremely prescriptive — it dictates exact file paths, type signatures, and implementation details). This plan's job is therefore **not** to re-design anything, but to sequence execution, apply the `Soma → Eidos` rename, and resolve the architectural issues in the spec before we commit them to code. Active research findings and design constraints live in [notes.md](notes.md).

### Constraints driving the plan

1. **Authoring happens on Windows; compilation and device validation happen on a Mac.** A Mac collaborator works alongside the Windows-side authoring. There is no longer a "Windows → Mac handoff" gating step — work flows continuously between both environments.
2. **Final validation requires a physical iPhone 13+.** MLX inference performance does not exist in the iOS Simulator. Simulator builds verify compilation and SwiftUI structure; "the app is actually fast and private" can only be proven on real hardware.
3. **Project name rename.** Everything in the spec says `Soma`; this project is `Eidos`. That touches: target names, bundle IDs, App Group ID (`group.com.soma.shared` → `group.com.eidos.shared`), entitlements files, `@main` struct name, Xcode targets, Info.plist strings, user-facing copy, and `systemPrompt` content.

### Mac handoff strategy

Rather than hand-authoring a fragile `.xcodeproj` bundle from Windows, we use **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — a YAML-driven project generator. We author a `project.yml` from Windows; the first Mac session runs `xcodegen generate && open Eidos.xcworkspace`. This is dramatically more reliable than editing `project.pbxproj` files from a non-Mac host, and it keeps the project description in a reviewable plain-text file going forward.

---

## Architectural changes & issues to resolve before coding

Research (April 2026) revealed four items in the spec that are not just "bugs to fix later" but **wrong choices given what now exists**. They change the shape of several files. The first four are the significant architectural changes; the rest are smaller corrections.

### Major architectural changes

**A1. Replace MediaPipeTasksGenAI with MLX Swift (NOT LiteRT-LM).**
The architecture.md spec uses MediaPipeTasksGenAI, which Google deprecated in April 2026. The natural successor would be LiteRT-LM (`google-ai-edge/LiteRT-LM`), but **its Swift API is "🚀 In Dev" with no release date** as of v0.10.1 (current). Phase 2 research therefore pivoted to **MLX Swift** (`github.com/ml-explore/mlx-swift` + `mlx-swift-examples`) — Apple's first-party on-device ML framework with a stable Swift API, SPM distribution, native Metal/Apple Silicon execution, working iOS reference apps (`LLMBasic`, `LLMEval`, `MLXChatExample`), `AsyncThrowingStream` token streaming, and HuggingFace model loading by ID. Gemma 4 lives at `mlx-community/gemma-4-E2B-it-4bit` and `mlx-community/gemma-4-E4B-it-4bit` in MLX-compatible format. Impact: `Podfile` is deleted (MLX is SPM-only), `GemmaSession` wraps MLX `ModelContainer`, `ModelDownloader` uses MLX's `Hub` API, `ModelConfig.GemmaVariant` uses HF IDs instead of raw `.task`/`.litertlm` URLs. See [notes.md](notes.md) "Implementation Research" for the full rationale and "Phase 2 — Inference Bring-Up" below for the file-by-file plan.

**A2. Use Gemma 4's native function calling instead of two-pass skill detection.**
Gemma 4 E2B and E4B both ship with native function calling and constrained-decoding structured output. The spec's `RAGPipeline` does a **non-streaming `generateBlocking` call just to detect a tool invocation, then a second streaming `generate` call for the chat response** — two full inference passes per user message. On-device, that's brutal: ~2× latency and ~2× energy per turn. The correct pattern now is: pass the tool schemas in the initial prompt using Gemma 4's function-calling format, let the model emit a structured call (or free text) in a single streaming pass, and detect the call on the token stream. Impact: `RAGPipeline.swift`, `PromptTemplates.swift`, and `SkillParser.swift` are substantially different. Also removes the need for `toolSystemPrompt` as a separate template.

**A3. Replace MiniLM + WordPiece + CoreML with Apple `NLContextualEmbedding`.**
iOS 17 ships `NLContextualEmbedding` — a BERT-based, contextual sentence-embedding model, built into the Natural Language framework, running on the Neural Engine, with zero setup and zero bundled weights. Using it **eliminates**: `convert_minilm.py`, the ~90MB `MiniLM.mlpackage` bundled asset, the WordPiece tokenizer + `vocab.txt`, the entire `EmbeddingService` CoreML plumbing, and the "hash tokenizer silently produces garbage" failure mode. The embedding layer becomes a ~30-line wrapper. Impact: `Eidos/Embedding/EmbeddingService.swift` is rewritten to use `NLContextualEmbedding`; the `MiniLM.mlpackage` asset, `convert_minilm.py`, and `vocab.txt` are deleted from the plan. **Caveat to verify**: language coverage — need to confirm the user's target languages are supported. If not, fall back to a real MiniLM conversion. Default plan: English only for v1.

**A3-asset. First-launch asset download interacts with B14 (EgressGuard).** `NLContextualEmbedding.requestEmbeddingAssets()` downloads model weights from Apple's CDN on first launch — a second network exception beyond the Gemma model download. Rather than permanently whitelisting Apple's CDN in `EgressGuard` (which would dilute the "zero-egress after onboarding" promise), the onboarding flow runs asset preinstallation **before** `EgressGuard.install()` is called. Sequence at first launch: (1) user grants consent on `OnboardingView`, (2) `EmbeddingService.load()` runs `requestEmbeddingAssets()` if needed, (3) Gemma model downloads via `ModelDownloader`, (4) `EgressGuard.install()` arms the allowlist, (5) from this point on, every outbound request goes through the guard. On subsequent launches, assets are already cached and `EgressGuard.install()` runs immediately from `EidosApp.init`. Impact: `EidosApp.init` no longer installs the guard unconditionally; installation moves to `AppContainer.bootstrap()` after asset/model checks complete.

**A4. Replace `Task.detached` + `@MainActor.run` pattern with `ModelActor` for background embedding.**
Per Apple's SwiftData concurrency guidance and Apple Developer Forums (verified April 2026): `@Model` classes are **not** `Sendable` and cannot cross actor boundaries — passing a `KnowledgeEntry` into `Task.detached` is a Swift 6 strict-concurrency error and, per Apple, a genuine data race even in Swift 5 mode. The correct pattern is: (a) a dedicated `@ModelActor`-backed `KnowledgeBackgroundActor` that owns its own `ModelContext` spun from the shared `ModelContainer`, (b) pass `PersistentIdentifier` values between actors (these *are* `Sendable`), (c) re-fetch the model inside the target actor. The spec's `embedEntry` method will not compile under Swift 6. Impact: `KnowledgeRepository.swift` gains a sibling `KnowledgeBackgroundActor.swift` (new file), and `embedEntry` is rewritten to take a `PersistentIdentifier` and re-fetch.

### Smaller corrections

**B1. Reorder execution within a turn given A2.** With native function calling, the spec's order (retrieve → detect → generate) collapses into a single pass where the model itself decides whether to call a tool or answer from context. Retrieved KB context is injected once at prompt construction, and tool calls happen in the model's output stream. Natural consequence of A2, listed separately for visibility.

**B2. `ContactsSource.requestPermission()` logic bug.** `(try? await store.requestAccess(for: .contacts)) != nil` returns `true` even when the user denies. Must be `== true`.

**B3. `IngestionCoordinator.isWhatsApp` uses `try!` on a regex.** Force-try that can crash. Use a static regex literal or `(try? Regex(...))` with a safe fallback.

**B4. App Group ID rename.** `group.com.soma.shared` → `group.com.eidos.shared` in `ShareViewController`, `IngestionCoordinator`, both `.entitlements` files, and (manually, on the Mac) Xcode UI.

**B5. Missing skill implementations referenced by `AppContainer`.** `RemindersSkill`, `ContactsSkill`, `DigestSkill` are referenced in `AppContainer.init` but never defined in the spec. Phase 0 must create empty stub types for all three so the container compiles; Phase 4 fills them in.

**B6. `.complete` file protection for the SwiftData store + App Group files.** One-line change, big privacy win for a privacy-first app: the database and the Share Extension ingestion queue become readable only when the device is unlocked. Set `NSFileProtectionComplete` on the `ModelContainer` configuration and on files written by `ShareViewController`.

**B7. Model download hardening.** Before downloading a 3GB file, check `URL.volumeAvailableCapacityForImportantUsageKey`; after downloading, verify SHA256 against the known hash from the Hugging Face repo. Prevents two common failure modes (full disk → corrupt partial file, network truncation → opaque load-time crash).

**B8. Content-hash import dedup.** `KnowledgeEntry` gets a `contentHash` field (SHA256 of `content`). `KnowledgeRepository.insert` skips entries whose hash already exists. Re-importing a WhatsApp export or re-sharing the same URL becomes idempotent. ~15 lines.

**B9. Hybrid search (vector + keyword, always).** The spec falls back to keyword search only when embeddings are unavailable. Better: always run both and merge via Reciprocal Rank Fusion. Catches exact-match queries (names, dates, numbers) that semantic search underweights. Low cost since the keyword side is already implemented.

**B10. Chat persistence during streaming.** The spec writes the assistant message to SwiftData only after generation completes. A crash or force-quit mid-stream loses the response. Flush incrementally (e.g., every N tokens or every 500ms) to `ConversationMessage.content`. Critical on-device where long generations are the norm.

**B11. Thermal & low-power guards in `GemmaSession`.** Observe `ProcessInfo.thermalStateDidChangeNotification`: on `.serious` reduce `maxTokens`, on `.critical` pause generation with a user-visible banner. Check `ProcessInfo.isLowPowerModeEnabled` before model warmup and before starting background embedding work. The spec lists this as a "Phase 5 TODO" but doesn't design it; this plan elevates it into `GemmaSession` from day one because it directly affects whether the app survives a long chat on a hot phone.

**B12. Locale-aware WhatsApp importer.** The spec's regex `^\[(dd/mm/yyyy), (hh:mm:ss)\]` is iOS UK/EU format only. US exports use `[m/d/yy, h:mm:ss AM/PM]`, and there are several other locale variants. Ship two or three patterns and try each.

**B13. Real MIME parsing in `MailImporter`.** The spec's mbox parser does naive `"\nFrom "` splitting and treats the body as plain text. ~90% of real email is multipart MIME with base64 or quoted-printable encoding and HTML bodies. Naive parsing produces garbage. Needs a real MIME decoder for `Content-Transfer-Encoding`, a HTML→text step (`NSAttributedString.init(html:)`), and attachment stripping.

**B14. Egress guard (auditable privacy).** The app's core promise is zero network after model download. Nothing in the spec *enforces* this — a future feature or dependency could break the guarantee silently. Ship a custom `URLProtocol` registered at launch that blocks all outbound traffic except the exact Hugging Face model URL, and only while `ModelDownloader.isDownloading == true`. Small, auditable, and turns the privacy claim into a property the code can prove.

**B15. Testability & smoke tests.** The spec has no test target. Add an `EidosTests` target with unit tests for: `TextChunker` boundaries, `WhatsAppImporter` regex against fixture exports, `MailImporter` against an mbox fixture, `VectorStore.topK` math, `SkillParser` on malformed and valid structured output, content-hash dedup. Personal assistants that touch real user data cannot ship with zero tests.

---

## Phased execution plan

Each phase ends in a concrete milestone. Authoring happens on Windows; compilation and device validation happen on a Mac in parallel. The "Status" section at the bottom of this file tracks current progress.

### Phase 0 — Scaffolding (Windows, current)

**Goal**: a fully-authored-but-unbuilt Eidos project tree that a Mac can pick up and generate. Reflects architectural decisions A1–A4.

**Tasks**:
- Create directory tree under the repo root matching architecture.md §3, with `Soma` → `Eidos` throughout, **with these deletions from the spec's tree**: `Embedding/MiniLM.mlpackage/` (replaced by A3), `convert_minilm.py` (no longer needed), `Embedding/vocab.txt` (no longer needed)
- **Add to the tree** (new files not in spec): `Eidos/KnowledgeBase/KnowledgeBackgroundActor.swift` (A4), `Eidos/Platform/EgressGuard.swift` (B14), `EidosTests/` target (B15)
- Author `project.yml` (XcodeGen) declaring three targets: `Eidos` (iOS app), `EidosShareExtension`, and `EidosTests` (XCTest), iOS 17 minimum, Swift 6 strict concurrency on, App Group `group.com.eidos.shared`
- Author a **deferred inference dependency** — Phase 0 leaves LiteRT-LM integration as a documented TODO in `project.yml` / `Podfile`, because its iOS distribution mechanism must be confirmed on the first Mac session (A1). The MediaPipeTasksGenAI references from the spec are **removed**, not carried forward.
- Author `Info.plist` with Eidos-branded usage description strings, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`
- Author `Eidos.entitlements` and `EidosShareExtension.entitlements` with App Group `group.com.eidos.shared`
- Author empty-but-compilable stubs for every file in the tree — every type the `AppContainer` references must exist as at least an empty struct/actor/class, so the container compiles from day one
- Author `EidosApp.swift` `@main` entry with `.complete` file protection configured on the `ModelContainer` (B6) and `EgressGuard.install()` called at launch (B14, stub for now)
- Author `README.md` documenting the Mac handoff
- Author `.gitignore` covering `Pods/`, `*.xcworkspace`, `DerivedData/`, `.build/`, `*.task`

**Milestone**: the tree exists, every file is syntactically valid Swift, every referenced type compiles, and handing the project to a Mac with XcodeGen installed produces an openable workspace.

### Phase 1 — Persistence, Embeddings, Repository (Windows authoring)

**Goal**: the entire knowledge-base pipeline authored in its real form, ready to compile as soon as a Mac is available. Applies A3 (NLContextualEmbedding) and A4 (ModelActor pattern) throughout.

**Tasks**:
- Fill in `Eidos/KnowledgeBase/KnowledgeEntry.swift` — all `@Model` classes from spec §4, plus `contentHash: String` field on `KnowledgeEntry` (B8)
- Fill in `Eidos/KnowledgeBase/TextChunker.swift` per spec §7.1
- Fill in `Eidos/Embedding/VectorStore.swift` per spec §6.2 (Accelerate vDSP dot-product) — unchanged from spec
- **Rewrite** `Eidos/Embedding/EmbeddingService.swift` using `NLContextualEmbedding` (A3). No CoreML, no WordPiece, no bundled model. ~30-line actor. Includes one-time `requestAssets` for the language model on first launch.
- Fill in `Eidos/KnowledgeBase/KnowledgeRepository.swift` (MainActor, UI-facing CRUD + search) — but `embedEntry` is removed from this file
- **New file**: `Eidos/KnowledgeBase/KnowledgeBackgroundActor.swift` — `@ModelActor`-backed actor that owns its own `ModelContext` from the shared `ModelContainer`. Takes a `PersistentIdentifier`, re-fetches the entry, runs chunking + embedding, writes `EmbeddingRecord` rows via its own context (A4).
- Implement B8 (content-hash dedup) in `KnowledgeRepository.insert`
- Implement B9 (hybrid vector + keyword search with Reciprocal Rank Fusion) in `KnowledgeRepository.search`

**Milestone**: hand-review confirms every file compiles cleanly against Swift 6 strict concurrency rules, the embedding pipeline has no CoreML / tokenizer / bundled-asset surface area, and background embedding uses the `ModelActor` pattern end-to-end.

### Phase 2 — Inference Bring-Up

**SUPERSEDED.** The detailed Phase 2 plan now lives in the "Phase 2 — Inference Bring-Up (active)" section near the bottom of this file. Major change: pivoted from LiteRT-LM (Swift API not yet released) to **MLX Swift** — see §A1 (revised) and [notes.md](notes.md) for rationale.

### Phases 3–6 — Feature Build-Out

These correspond to architecture.md §17 Phases 2–5, with changes folded in from A2, B10, B12, B13.

- **Phase 3 — RAG + single-pass chat with tools**: `RAGPipeline` (single-pass with Gemma 4 function calling, not two-pass — A2), `ContextBuilder`, streaming chat with incremental `ConversationMessage` flush (B10), `KBBrowserView`, `SpeechTranscriber`, voice note flow. Milestone: "what notes do I have about X?" returns correct entries AND "add a note that says Y" dispatches to `AddNoteSkill` in the same turn.
- **Phase 4 — iOS platform sources + skills**: `CalendarSource`, `ContactsSource` (with B2 fix), `SkillProtocol`, `SkillRegistry`, `SkillParser` (structured-output parsing — A2), `AnyCodable`, all 6 built-in skills, permission flow, `DigestGenerator`, `HomeView`. Milestone: "what's on my calendar this week?" works end-to-end.
- **Phase 5 — Share Extension + ingestion**: `ShareViewController` (with `.complete` file protection — B6), App Group queue, `IngestionCoordinator` (with B3 regex fix), `WhatsAppImporter` (multi-locale — B12), `MailImporter` (MIME + HTML→text — B13), `PlainTextImporter`, `IngestView`, content-hash dedup surfaced in results (B8). Milestone: share a WhatsApp `.txt` → messages appear in search, re-share shows "0 new".
- **Phase 6 — Polish + tests**: `SettingsView` (model swap, skill toggles, clear KB, egress guard status), haptics, launch screen, app icon, background digest via `BGAppRefreshTask`, full `EidosTests` smoke suite (B15). Milestone: ship-ready build, tests green on Mac CI.

---

## Critical files

**To be created in Phase 0 (Windows-authorable)**:

- `project.yml` — **NEW** (replaces `.xcodeproj` hand-authoring)
- `Podfile` — skeleton only, LiteRT-LM integration deferred to Phase 2 (A1)
- `README.md` — **NEW** (Mac handoff instructions)
- `.gitignore` — **NEW**
- `Eidos/Resources/Info.plist`
- `Eidos/Resources/Eidos.entitlements`
- `EidosShareExtension/EidosShareExtension.entitlements`
- `Eidos/App/EidosApp.swift` — `@main`, with `.complete` file protection (B6) and `EgressGuard.install()` (B14)
- `Eidos/App/AppContainer.swift`
- `Eidos/App/AppRouter.swift`
- `Eidos/Platform/EgressGuard.swift` — **NEW** (B14)
- `EidosTests/` — **NEW** test target (B15)
- Stub files (empty compilable types) for every other file in architecture.md §3 tree, renamed

**Deletions from the spec's §3 tree** (consequence of A3):

- ~~`Eidos/Embedding/MiniLM.mlpackage/`~~ — replaced by `NLContextualEmbedding`
- ~~`convert_minilm.py`~~ — no longer needed
- ~~`Eidos/Embedding/vocab.txt`~~ — no longer needed

**To be filled in during Phase 1 (Windows-authorable)**:

- `Eidos/KnowledgeBase/KnowledgeEntry.swift` — SwiftData models + `contentHash` (B8)
- `Eidos/KnowledgeBase/TextChunker.swift`
- `Eidos/KnowledgeBase/KnowledgeRepository.swift` — with hybrid search (B9) and dedup (B8)
- `Eidos/KnowledgeBase/KnowledgeBackgroundActor.swift` — **NEW**, `@ModelActor` (A4)
- `Eidos/Embedding/VectorStore.swift`
- `Eidos/Embedding/EmbeddingService.swift` — rewritten as `NLContextualEmbedding` wrapper (A3)

**Reference**:

- [architecture.md](architecture.md) is the canonical spec for types, signatures, and UI structure. Every Swift file we author should match it exactly except where this plan explicitly documents a deviation.

---

## Verification

Phases 0–1 cannot be runtime-verified from Windows — there is no Swift iOS toolchain here. Verification is staged:

**Phase 0 (Windows)**:
- [ ] Every file in architecture.md §3 tree exists under the repo root with `Soma→Eidos` rename applied
- [ ] No occurrence of `Soma` or `com.soma` remains anywhere (Grep check)
- [ ] `project.yml` is valid YAML and references existing file paths
- [ ] Every referenced type in `AppContainer.init` has at least a stub definition

**Phase 1 (Windows)**:
- [ ] Hand-review each filled-in file against its spec section
- [ ] Confirm `@Model` objects never cross actor boundaries in authored code
- [ ] `NLContextualEmbedding` usage matches Apple's documented API surface

**Phase 2 verification** is detailed in the "Phase 2 — Inference Bring-Up (active)" section below.

Per-phase milestones beyond Phase 2 are inherited from architecture.md §17 and remain the acceptance criteria for each subsequent phase.

---

## Status

- **Phase 0 — Scaffolding**: ✅ Done. 66 files authored under `Eidos/`, full directory tree, `project.yml` (XcodeGen), Info.plist, entitlements, compilable stubs for every layer.
- **Phase 1 — Persistence + Embeddings + Repository**: ✅ Done. `EmbeddingService` rewritten on `NLContextualEmbedding` (mean-pool + L2 normalize), `KnowledgeRepository` with hybrid RRF search + content-hash dedup, `KnowledgeBackgroundActor` as `@ModelActor` with `PersistentIdentifier` handoff, AppContainer wires everything, real unit tests for chunker/vector store/RRF. `EgressGuard.install()` moved out of `EidosApp.init` into `AppContainer.bootstrap()` per §A3-asset.
- **Phase 2 — Inference Bring-Up**: 🚧 Active. Pivoted from LiteRT-LM to MLX Swift. Detail below.
- **Phases 3–6**: Pending Phase 2.

---

## Phase 2 — Inference Bring-Up (active)

**Goal**: a user types a prompt on a real iPhone 13+ and watches Gemma 4 stream a response. Fully offline, EgressGuard armed (allowing the one-time model download). No RAG, no skills, no KB injection. Just `User → ChatView → ChatViewModel → GemmaSession → MLX → tokens back`.

This is the milestone that proves the inference plumbing in isolation, before Phase 3 layers RAG on top.

### Decisions baked in (from user)

1. **Default variant: E2B** with explicit "upgrade to E4B" path in Settings. E4B is hidden behind a device-capability check (iPhone 13 base only has ~2.2 GB usable RAM — see [notes.md](notes.md) Design Constraints).
2. **Function-calling template plumbed in Phase 2**, even though Phase 3 wires it to skills. `ModelConfig.toolSchemasJSON` flows through `PromptTemplates.chat(...)` from day one.
3. **`ChatView` empty state copy**: "Model not installed — download in Settings." Concrete, not euphemistic. Tapping the CTA opens the onboarding/download flow.
4. **Model storage location**: `~/Library/Application Support/Models/` — invisible to the Files app, same on-device guarantees as Documents.
5. **Async warmup**: model load runs in `AppContainer.bootstrap()` after onboarding; `ChatView` shows "warming up..." until `GemmaSession.isLoaded == true`.

### Sub-phases (executed in this order)

**2.0 — Add MLX Swift dependency.** Update `project.yml` to add `mlx-swift-examples` as an SPM package dependency (it transitively pulls in `mlx-swift`). Mac collaborator runs `xcodegen generate`, confirms the project resolves and builds with the existing Phase 1 code unchanged. Delete the now-irrelevant `Podfile` (MLX is SPM-only, no CocoaPods needed).

**2.1 — Real `EgressGuard` ([Eidos/Platform/EgressGuard.swift](Eidos/Platform/EgressGuard.swift)).** Implement the `URLProtocol` subclass. Requests are blocked unless: (a) the target host matches the allowlist AND (b) `isModelDownloadInProgress == true`. The MLX model loader uses the standard `URLSession` machinery so it goes through this guard. Tests: register the protocol on a `URLSessionConfiguration`, assert blocked vs allowed for both gate states.

**2.2 — Real `ModelDownloader` ([Eidos/Inference/ModelDownloader.swift](Eidos/Inference/ModelDownloader.swift)).** Becomes a thin wrapper around MLX's HuggingFace model fetch (`mlx-swift-examples` exposes a `Hub` snapshot API). Wraps the MLX call inside a `do { EgressGuard.isModelDownloadInProgress = true; defer { ... = false }; ... }` block so the egress guard temporarily opens. Adds: disk-space preflight via `URLResourceValues.volumeAvailableCapacityForImportantUsageKey` (B7), per-variant SHA256 verification skipped (MLX validates flatbuffer integrity itself), progress observation forwarded to `@Observable` properties for UI.

**2.3 — Real `ModelConfig` ([Eidos/Inference/ModelConfig.swift](Eidos/Inference/ModelConfig.swift)).** `GemmaVariant` rewritten:

```swift
enum GemmaVariant: String, CaseIterable, Sendable {
    case e2b = "mlx-community/gemma-4-E2B-it-4bit"
    case e4b = "mlx-community/gemma-4-E4B-it-4bit"

    var displayName: String { ... }
    var huggingFaceID: String { rawValue }
    var approximateDiskBytes: Int64 { ... }   // ~1.5 GB / ~3 GB
    var requiresDeviceClass: DeviceClass { ... }   // .standard / .pro
}
```

Adds `ModelConfig.toolSchemasJSON: String?` and `ModelConfig.functionCallingEnabled: Bool` plumbed through to `PromptTemplates`. The exact mlx-community model IDs are confirmed by the Mac collaborator on first build (the Hub IDs above are best-guess from research — see [notes.md](notes.md)).

**2.4 — Real `GemmaSession` ([Eidos/Inference/GemmaSession.swift](Eidos/Inference/GemmaSession.swift)).** Wraps MLX Swift's LLM session pattern:

```swift
import MLX
import MLXLLM
import MLXLMCommon

actor GemmaSession {
    private var modelContainer: ModelContainer?
    private(set) var isLoaded = false

    func load(modelPath: String, config: ModelConfig) async throws {
        let configuration = ModelConfiguration(directory: URL(filePath: modelPath))
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        )
        isLoaded = true
    }

    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let modelContainer else {
                    continuation.finish(throwing: GemmaError.notLoaded)
                    return
                }
                do {
                    try await modelContainer.perform { context in
                        let input = try await context.processor.prepare(
                            input: .init(prompt: prompt)
                        )
                        let stream = try MLXLMCommon.generate(
                            input: input,
                            parameters: .init(),
                            context: context
                        )
                        for await event in stream {
                            if case .chunk(let text) = event {
                                continuation.yield(text)
                            }
                        }
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

Exact MLX class/method names (`LLMModelFactory`, `ModelContainer`, `MLXLMCommon.generate`) are pulled from `mlx-swift-examples/Applications/LLMEval` which is the canonical reference. Thermal guards (B11) check `ProcessInfo.thermalState` between tokens and halt on `.critical`.

**2.5 — Real `PromptTemplates` ([Eidos/Inference/PromptTemplates.swift](Eidos/Inference/PromptTemplates.swift)).** Gemma 4 chat format. The model uses standard `system`/`user`/`assistant` roles (per Gemma 4 docs); MLX's `UserInput` accepts these as message arrays so we don't have to hand-format `<start_of_turn>` tokens. Function calling is plumbed via `tools:` parameter in `UserInput` if the MLX API supports it (else: prepend a tool schema preamble to the system message). Snapshot tests against fixed expected output strings.

**2.6 — Onboarding UI.**
- `OnboardingView`: 3-step wizard. Welcome (privacy promise) → variant pick (E2B default, E4B grayed if device class is `.standard`) → download button.
- `ModelDownloadView`: real progress bar bound to `ModelDownloader.progress`, cancel, error states, "ready ✓" final state.
- `EidosApp` decides: if `modelDownloader.modelPath(for: defaultVariant) == nil`, show `OnboardingView` instead of `RootView` until done.

**2.7 — Minimal Chat path.** `ChatViewModel.send()` calls `gemma.generate(prompt:)` via a flat `PromptTemplates.chat(history:userMessage:retrievedContext:"", toolSchemasJSON: nil)` (no RAG yet). Streams tokens into `streamingBuffer` (already exists from Phase 0). On completion, persists the full message via SwiftData. **B10 (incremental flush) is deferred to Phase 3** alongside RAG. `ChatView` empty state when `gemma.isLoaded == false`: "Model not installed — download in Settings" with a tap-to-onboard CTA.

**2.8 — Real-device validation (Mac collaborator).** Install on iPhone 13+. Run through onboarding. Type a prompt. Watch streaming. **Airplane-mode test**: verify chat keeps working with all radios off. Inspect EgressGuard log: zero blocked or allowed requests during chat (only during the model download window).

### Files modified in Phase 2

| File | Change |
|---|---|
| `project.yml` | Add `mlx-swift-examples` SPM dependency, drop `Podfile` reference |
| `Podfile` | **Delete** — MLX is SPM-only |
| `Eidos/Platform/EgressGuard.swift` | Stub → real `URLProtocol` implementation |
| `Eidos/Inference/ModelConfig.swift` | Stub → real `GemmaVariant` with HF IDs + device class + function-calling option |
| `Eidos/Inference/ModelDownloader.swift` | Stub → wrap MLX `Hub` snapshot, EgressGuard cooperation, disk preflight |
| `Eidos/Inference/GemmaSession.swift` | Stub → real MLX `ModelContainer` + `AsyncThrowingStream` generation |
| `Eidos/Inference/PromptTemplates.swift` | Stub → real Gemma 4 chat formatting + function-calling plumb-through |
| `Eidos/UI/Onboarding/OnboardingView.swift` | Stub → 3-step wizard with variant picker |
| `Eidos/UI/Onboarding/ModelDownloadView.swift` | Stub → real progress UI |
| `Eidos/UI/Chat/ChatView.swift` | Empty-state copy + onboard CTA |
| `Eidos/UI/Chat/ChatViewModel.swift` | Real `send()` consuming `gemma.generate(prompt:)` |
| `Eidos/App/AppContainer.swift` | Add device-class detection, pick default variant, wire async warmup |
| `Eidos/App/EidosApp.swift` | Branch on "model installed?" to show Onboarding vs RootView |
| `EidosTests/EgressGuardTests.swift` | **New**. URLProtocol gate behavior. |
| `EidosTests/PromptTemplatesTests.swift` | **New**. Snapshot of chat format. |
| `EidosTests/ModelDownloaderTests.swift` | **New**. Disk preflight, progress observation. |

### Verification

**Unit (Mac CI, no device)**:
- `EgressGuardTests`: blocked requests fail, allowed requests succeed only when gate is open
- `ModelDownloaderTests`: disk preflight rejects when synthetic free space is low; progress publishes monotonically
- `PromptTemplatesTests`: snapshot matches a fixed expected string for a known message history

**Integration (device required)**:
1. Install on iPhone 13 (base) → onboarding shows E2B default, E4B disabled with "requires iPhone 13 Pro or later"
2. Download completes → tab bar unlocks → ChatView ready
3. "hello" → response streams in
4. Toggle airplane mode → ask another → response still streams
5. Force-quit + relaunch → async warmup, chat ready within 10–20s
6. Inspect `EgressGuard.log` (debug-only): zero outbound requests during chat sessions

### Out of Phase 2 scope

- RAG (Phase 3)
- Skill dispatch (Phase 4) — function calling is *plumbed* but no skills wired up yet
- Share extension (Phase 5)
- Settings model swap, advanced options, BG warmup (Phase 6)
- B10 incremental persistence during streaming (Phase 3 alongside RAG)
- Multi-conversation persistence (Phase 3)

---

Research findings and design constraints that informed this plan live in [notes.md](notes.md). Read that first if you're picking up Phase 2 cold.
