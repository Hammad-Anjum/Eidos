# HANDOFF.md — Claude-to-Claude status (2026-05-14)

> Written for the cofounder's Claude. Dense, no preamble.
> Branch `AuADHD`, HEAD `ea48a66`. 4 days to Kaggle submission
> (deadline 2026-05-18 23:59 UTC). Mac verify is the blocker.

---

## What Eidos is in one paragraph

On-device AuDHD (autism + ADHD overlap) companion. Single iOS app
(`Eidos` scheme, xcodegen project). Gemma 4 E2B (4-bit, ~1.5 GB) on
MLX Swift. Zero network egress after the one-time model download —
`EgressGuard` is a `URLProtocol` that fails-closed. Four voice/camera-
first Home tiles → tool-calling RAG chat backed by markdown-on-disk
memory + Apple `NLContextualEmbedding` semantic recall. Crisis
language is intercepted pre-LLM by a hardcoded `SafetyGate`. Demo
target: physical iPhone 15 Pro+. Mac (Designed for iPad) is the dev
runtime; iOS Simulator runs canned mocks (MLX Metal crashes there).

---

## DI graph (read `Eidos/App/AppContainer.swift` for the source)

```
GemmaSession (actor, the only inference path via runGuardedGeneration)
   ↑
RAGPipeline ──── ContextBuilder ─── MemoryManager (actor)
   │                  │                  ↑
   │                  └─ MemoryRecallService ──── VectorStore
   │                          │                       ↑
   │                          └─ EmbeddingService (NLContextualEmbedding)
   │
   ├── SkillRegistry: [BreakDownScene, VoiceJournalCapture,
   │                   RecallRelevantMemories, PickNextTask]
   ├── SafetyGate (pre-LLM, hardcoded regex)
   └── AmbientSnapshotAssembler (location/cal/health for "right now" block)

MemoryManager.onSave ──hook──▶ MemoryRecallService.indexEntry
   (wired in AppContainer.bootstrap — every save fans out to recall)

MemoryCrystallizer (ADD/UPDATE/DELETE/NONE reconciliation) is wired
but NOT used by VoiceJournalCaptureSkill — v1 saves journals verbatim.
```

---

## What ships today (commit-tagged)

| Surface | Trigger | Path |
|---|---|---|
| **Look** | Home camera tile → CGImage | `BreakDownSceneSkill.invoke` returns spoken 3-step plan; persists a P3 `.recentSession` entry tagged `scene`/`look-mode` |
| **Ground** | Home tile or chat trigger phrases | Prompt-section response. No tool. Script: acknowledge → 5-4-3-2-1 → breath → ONE action. **No trailing question.** |
| **Journal** | Full-screen `JournalRecordingView` | `VoiceJournalCaptureSkill` imperative (bypasses Gemma). Verbatim transcript → `MemoryEntry` (.recentSession, P3). Auto-indexed via `onSave` hook. Recovery file on save failure. |
| **What Now** | Home tile (reads `@AppStorage` energy) or voice | `PickNextTaskSkill` reads `activePriorities` + `CalendarSource` → ONE pick + 2/5/10-min commitment by energy band |
| **Recall** | "what did I say about…" phrasing | `RecallRelevantMemoriesSkill` chat tool, threshold 0.30, topK 3 |
| **Crisis bar** | Home "I need help now" | Opens `CrisisResourcesView` directly (988/911/text/grounding). Does NOT touch chat or Gemma. |
| **Speaker button** | Per assistant bubble + global "Repeat last" | `SpeechSynthesizer.shared.speak()` / `.repeatLast()` |
| **Identity onboarding** | First launch (step 3 of 5) | Name → UserDefaults; purpose → P1 `MemoryEntry` in `.coreIdentity` (auto-indexed) |

---

## Architectural invariants (DO NOT BREAK)

1. **All inference goes through `GemmaSession.runGuardedGeneration`.**
   FIFO lock + `MLX.Memory.clearCache()` + thermal abort + memory
   pre-flight live there once. Don't sprinkle these elsewhere.
2. **`RAGPipeline.chat` is bounded.** `DeviceProfile.maxToolHops`:
   iPhone 2 / iPad 4 / Mac 5. Thermal re-checked at every hop.
   Tool results bundle back into next prompt — no parallel fan-out.
3. **`chatLite` system prompt is ASCII-only.** No markdown headers,
   smart quotes, em-dashes, or `instruction-content`-shaped strings.
   v12 stability invariant — name injection in IdentityStep
   sanitizes diacritics + checks `allSatisfy { $0.isASCII }`.
4. **`MemoryManager.save(_:reindex:)` fans out to recall via `onSave`.**
   `touch(id:)` passes `reindex: false` (no source change ⇒ no
   re-embed). Never add a persistence path that bypasses `save()`.
5. **`ContextBuilder.build(query:)`** merges rule-based (P1 +
   activePriorities + topK topic) with semantic recall ≥0.40.
   `memoryRecall` is optional on the struct so legacy tests compile.
6. **`SafetyGate.evaluate(_:)` runs BEFORE retrieval.** Crisis hits
   return a hardcoded stream. Never let Gemma improvise on crisis.
7. **`EidosFeatureFlags.shared.minimalChatPromptEnabled` defaults
   ON in iPhone Release** to avoid prefill OOM. **It bypasses the
   tool catalogue.** Flip OFF on the demo build via Settings →
   Diagnostics → Flags. This is the single highest-cost mistake
   on demo day.
8. **Markdown files are source of truth.** SwiftData / FTS5 /
   VectorStore are derived artifacts rebuilt from `Documents/memory/<tier>/<id>.md`.

---

## Files that matter most (by frequency of touch)

| Path | Why |
|---|---|
| `Eidos/App/AppContainer.swift` | DI graph. The shape of the app. |
| `Eidos/Inference/GemmaSession.swift` | `runGuardedGeneration`. Read before touching inference. |
| `Eidos/Inference/PromptTemplates.swift` | `systemPrompt` + AuADHD addendum + `chatLite` ASCII invariant |
| `Eidos/RAG/RAGPipeline.swift` | Tool loop, SafetyGate, prompt assembly, vision/audio params |
| `Eidos/RAG/ContextBuilder.swift` | Rule-based + semantic recall merge |
| `Eidos/Memory/MemoryManager.swift` | `save`/`touch`/`onSave` hook |
| `Eidos/Memory/MemoryRecallService.swift` | `recall(query:topK:minScore:)` + `indexEntry(_:)` |
| `Eidos/Skills/Builtin/*.swift` | The 4 skills |
| `Eidos/UI/Home/HomeView.swift` | Tiles + energy slider + crisis bar |
| `Eidos/UI/Onboarding/{OnboardingView,IdentityStep}.swift` | 5-step onboarding |
| `Eidos/Platform/Diagnostics/EidosFeatureFlags.swift` | `minimalChatPromptEnabled` + `speakRepliesEnabled` + `longContextPackingEnabled` |
| `Eidos/Platform/Diagnostics/BenchmarkCorpus.swift` | `auADHD` category, 4 fixtures |

---

## Recent commit chain (read these for context)

```
ea48a66  RAG fix: auto-index on save + semantic recall in ContextBuilder
72ec6e8  latest code push with updated bug fixes and better stability
         (Phase 3.5: speaker button, crisis tile, onboarding refresh,
          IdentityStep name/purpose; misc hardening)
9e88070  Mark NEXT_PHASES.md checkpoints — Phases 2 + 3 complete
be14a84  Phase 3: AuADHD Home UX (4 tiles + energy slider + journal mic + dispatch)
eede6ee  Days 1-2: AuADHD prompt addendum + 4 skills + benchmark fixtures
b477741  Add NEXT_PHASES.md — 6-day AuADHD execution playbook
```

---

## What's left — ordered by criticality

### 🔴 Blocker — Mac build verify (cofounder, ~30 min)

```bash
git fetch origin && git checkout AuADHD && git pull
xcodegen generate
xcodebuild build -scheme Eidos \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Windows host where this branch was authored has no MLX runtime.
**Everything past this assumes a clean build.** If it fails: most
likely an orphan symbol or SwiftData migration. `xcrun simctl erase
all` + patch on top. Do NOT amend prior commits.

### 🔴 Reliability gate — `auadhd.scene.tool` ≥85% on 20-iter sweep

`BenchmarkCorpus.auADHD` has 4 fixtures. The hero is
`auadhd.scene.tool` — vision+tool-call combo. Run 20 iterations
against a real cluttered-desk photo. If <85%:

- Retune the **Visual overwhelm** section in
  `PromptTemplates.systemPrompt` AuADHD addendum (~4h).
- If still <85% by EOD: cut `BreakDownSceneSkill` + `PickNextTaskSkill`
  from v1; pivot demo to Ground + Journal as primary.

### 🟡 Demo prep (Day 5–6, founder)

1. **Pre-seed `activePriorities`** — DEBUG-only auto-seed in
   `AppContainer.bootstrap()`. 5–8 entries. Without this, `pick_next_task`
   returns empty-state during demo. (Founder may seed manually instead.)
2. **tcpdump audit** — `rvictl -s <udid>; sudo tcpdump -i rvi0 -w eidos.pcap`.
   Verify zero packets during the 4-surface flow. Screenshot goes in write-up.
3. **Demo shoot** — script in `plans/alright-lets-pivot-this-rippling-snowflake.md`
   under "Demo video script (3:00)". Founder solo with VoiceOver
   + screen curtain. Multiple takes per surface. Mac (Designed for iPad)
   as backup if iPhone OOMs on every take.

### 🟢 Submission paperwork (Day 6–7)

- Edit demo video; upload unlisted YouTube.
- 2-page technical write-up (sections in `NEXT_PHASES.md` § 5b).
- `git tag -a v1.0.0-hackathon -m "..."` + push.
- Make repo public.
- Submit on Kaggle competition page.

---

## Known asymmetries / debt (don't fix during the sprint)

- **chatLite vs full chat memory paths differ.**
  - chatLite: pulls top-k via `MemoryRecallService.recall` directly,
    threshold 0.30, no rule-based base set.
  - Full chat: `ContextBuilder` merges rule-based + semantic ≥0.40.
  - V2 should unify; sprint cost is just "set min_score per path."
- **`MemoryManager.delete(id:)` does NOT notify recall.** Real bug.
  Demo doesn't exercise deletes. V2.
- **`MemoryCrystallizer.indexEntry` + `IdentityStep.indexEntry` calls
  are now redundant** because the `onSave` hook covers them.
  Defense-in-depth; leave them.
- **`## From your notes` (KB) is empty.** AuADHD branch has no
  ingestion path (no MedlinePlus, no user docs). Dead-code rendering
  stays — costs nothing.
- **Multilingual claim in write-up is weak.** Apple `SFSpeechRecognizer`
  is 50+ langs; Gemma 4 E2B is multilingual; we never tested it. If
  the write-up claims this, do a single non-English smoke test first.
- **`audhdMode` 3-way picker not built.** v1 is AuDHD-default only.

---

## What NOT to build during this sprint

- No new skills.
- No multi-step tool chains (`RAGPipeline.chat` is single-loop;
  changing this would break the prefill RAM bound on iPhone).
- No widget surface (`EidosWidget` target stays stubbed).
- No background tasks (`BGAppRefreshTask` reliability on iOS is bad;
  documented in research).
- No HealthKit biofeedback / sensory regulation.
- No diagnosis features (`SafetyGate` intercept territory).
- No app rename.
- No mode-toggle UI (deferred to v2).
- No real-user testing (founder solo with VoiceOver; document the
  limitation honestly in the write-up).

---

## How to think about the next Claude session

1. **Read `PRODUCT.md` first.** It's the source of truth.
2. **Read `CLAUDE.md` next.** Working rules.
3. **Then this file.** Status + paths.
4. **If touching memory or RAG**: read `MemoryManager.save(_:reindex:)`
   + the `onSave` wiring in `AppContainer.bootstrap` + `ContextBuilder.build`
   in that order. They form one contract.
5. **Before any inference change**: re-read `runGuardedGeneration` in
   `GemmaSession.swift`. The lock/cache/thermal/memory invariants live
   there exactly once for a reason.
6. **If a feature is missing**: check `NEXT_PHASES.md` § "What we
   explicitly do NOT ship in v1" before assuming it's a bug.
7. **Resist scope creep.** 4 days. Reliability sweep + demo shoot +
   write-up + submission is the entire remaining critical path.
