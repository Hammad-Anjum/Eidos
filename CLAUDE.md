# CLAUDE.md — Working rules for the Eidos AuADHD repo

> **Source of truth**: [`PRODUCT.md`](./PRODUCT.md). If this file and
> `PRODUCT.md` disagree, `PRODUCT.md` wins.

---

## On every turn

1. Read `PRODUCT.md` before making any design or scope decision.
2. If the user's ask is outside the AuADHD companion flow (4 surfaces
   — Look / Ground / Journal / What Now — plus the Inertia-default
   prompt section), surface the scope miss before starting. The
   submission window is bounded; resist scope creep.
3. Cross-check `runGuardedGeneration` invariants in
   `Eidos/Inference/GemmaSession.swift` before adding any inference path.
4. Verify the cofounder branch (4A accessibility track) hasn't shipped
   shared changes that conflict.

---

## Product principles

- **Zero egress after onboarding.** `EgressGuard` enforces it. Any new
  outbound call requires an explicit allowlist entry + retention-policy
  comment. Data brokers buy ADHD / depression / autism diagnoses; the
  user came here BECAUSE Eidos doesn't sell them out.
- **Markdown is the source of truth.** SwiftData / FTS5 / vector indexes
  are derived artifacts rebuilt from markdown. Memory files are the
  auditable trail the user can read and edit.
- **Safety-critical paths never reach the LLM.** Crisis intercept is
  `SafetyGate`'s job — hardcoded resources, never Gemma improvisation.
- **Companion, not coach.** Nowhere in user-visible copy do we use:
  "Doctor", "Therapist", "Coach". No diagnostic claims. No "you should",
  "you ought to", "you really need to." This is not a coach; it's a
  pocket presence.
- **Privacy is the moat**: feature decisions that weaken zero-egress get
  pushed back regardless of convenience.

---

## AuADHD-specific design rules (non-negotiable for this audience)

These are unique to this product. The audience drops apps that demand
the executive function they lack (54% drop within weeks, per the prior
research turn). Every UX decision lands against this filter.

1. **If a feature requires the executive function the user lacks, it's
   wrong.** No multi-step setup. No required onboarding choices. No
   "fill in your routine first." Defaults pick everything; advanced
   users toggle later.
2. **No gamification.** No streaks, no badges, no "you missed 3 days,"
   no motivational pet, no streak-saving virtual currency. Spoons
   explicitly rejects gamification; we follow that bar.
3. **No pathologizing language.** Not "stuck because of ADHD" but
   "stuck." Not "your autism is acting up" but "the day is heavy."
   Different wiring, not disorder.
4. **Voice-first by default.** AuDHD-prevalent traits include alexithymia
   and brain-stops-during-typing. Voice in, speech out, eyes-free where
   possible.
5. **One thing, then stop.** Decision-paralysis flows return ONE
   suggestion + a 5-minute commitment. Never lists of options. Never
   "or alternatively." Never "if that doesn't work, you could try."
6. **Never end with a follow-up question after grounding.** "Would you
   like to talk about it?" defeats the purpose of grounding. End the
   reply.
7. **Self-identification beats inference.** The user picks their mode
   (AuDHD / ADHD-only / autistic-only) in Settings. We do not try to
   detect their neurotype from their behavior — that's a
   SafetyGate-intercept territory and a trust-killer either way.

---

## Engineering bar (non-negotiable)

1. Every public API has `///` doc comments.
2. Every error path is a typed error. No raw `NSError`.
   `errorDescription` is UI-ready.
3. Swift 6 strict concurrency, zero warnings. Shared state is
   actor-isolated, `Sendable`, or `@unchecked Sendable` with a
   justifying comment.
4. No force-unwraps, no `try!`, no `fatalError` in production paths.
   `#if DEBUG` assertions only.
5. Zero silent failures. Every `catch { }` either logs or surfaces.
6. JSONL diagnostics with a stable schema. Crash-safe (background
   queue, never blocks UI).
7. Feature flags, not branches: `EidosFeatureFlags`.
8. Fails-closed on safety: `SafetyGate` is a hardcoded regex pre-LLM.

---

## Device-first mandate

Every code path that runs during generation or in a loop must:

- [ ] Read `DeviceProfile` to scale work by device class.
- [ ] Have `MemoryProbe.snapshot(tag:)` at entry + exit (DEBUG only).
- [ ] Respect the thermal guard (`GemmaError.thermalCritical` aborts
      cleanly).
- [ ] Use `async`/`await` — not `DispatchQueue.main.sync`, ever.
- [ ] Have a feature flag if experimental.

iPhone is the demo target; iPad/Mac (Designed for iPad) are dev-test
targets with more headroom. Default conservatively on iPhone.

---

## Architectural invariants (do not break)

- `runGuardedGeneration()` is the only entry into Gemma inference.
  Inference lock + MLX cache clear + thermal abort + memory pre-flight
  live there once.
- `MLX.Memory.clearCache()` runs between every generation on iPhone.
- Every TCC permission callback is `@Sendable`.
- `AVAudioSession` `.record` pairs with `.measurement` mode.
- ChatViewModel throttles streaming UI updates to ~60ms.
- `chatLite` system prompt is ASCII-only — no markdown headers, smart
  quotes, em-dashes, or instruction-content strings. **It is the only
  inference path that has been verified safe on iPhone Release.** The
  full `RAGPipeline.chat` path remains in the codebase for iPad / Mac
  / DEBUG, but on iPhone Release `minimalChatPromptEnabled` stays ON
  and `chatLite` carries every chat surface, including the AuADHD
  demo flows. Do not add demo-critical behavior to the full pipeline
  without first verifying that `chatLite` can carry it; if it has to
  live in the full path, the demo-day flag rule has to change too
  (and the OOM-jetsam class of bug has to be re-solved first).
- `chatLite`'s curated tool catalogue is capped at 3 by
  `SkillRegistry.availableSkills().prefix(3)`. The order of skill
  construction in `AppContainer` is load-bearing: the 3 chat-path
  tools (BreakDownScene, PickNextTask, RecallRelevantMemories) come
  first; imperative-only tools (VoiceJournalCapture, BodyDouble —
  dispatched directly from views) come after. Reordering this list
  silently breaks demo surfaces.
- `RAGPipeline.chat` runs a bounded tool loop, capped by
  `DeviceProfile.maxToolHops` (2 on iPhone, 4 on iPad, 5 on Mac).
  Thermal state is re-checked at every hop; `GemmaError.thermalCritical`
  aborts the loop cleanly. The cap is what keeps prefill RAM bounded
  on iPhone — never bump it without re-measuring the KV-cache
  ceiling. Each tool result is bundled back into the next prompt so
  there is no parallel fan-out.
- **Memory writes auto-index into recall.**
  `MemoryManager.save(_:reindex:)` fires an `onSave` closure hook
  after the disk write + in-memory index upsert. `AppContainer.bootstrap()`
  attaches the hook to `MemoryRecallService.indexEntry(_:)`, so every
  skill that persists a `MemoryEntry` becomes findable via semantic
  recall on the same turn — no per-caller `indexEntry` plumbing.
  `touch(id:)` passes `reindex: false` because the embedding source
  (title + body) is unchanged; re-embedding would burn Neural Engine
  time. Do NOT add persistence paths that bypass `save()` — the hook
  is what keeps the hero demo flow (journal → immediate recall)
  honest. (Commit `ea48a66`.)
- **`ContextBuilder.build(query:)` consults rule-based AND semantic
  recall, merged.** Rule-based: P1 + activePriorities + topK hot
  topic by recency. Semantic: `MemoryRecallService.recall` at
  threshold 0.40 (tighter than chatLite's 0.30 because rule-based
  already covers must-include cases). Merge preserves rule-based
  ordering and appends semantic hits the rules missed. Without this,
  `.recentSession` entries (fresh journal, breakdown scenes) were
  invisible to the full chat path. `memoryRecall` is optional on
  `ContextBuilder` so legacy / test call sites still compile; the
  production path in `RAGPipeline.init` threads it through.

---

## Demo-day operational rule (cofounder-facing)

**TWO flags must both be ON for the demo. Both default ON on iPhone
Release as of the 2026-05-19 structural fix; this section documents
*verification*, not configuration.**

| Flag | Default | Why |
|---|---|---|
| `minimalChatPromptEnabled` | ON | Full RAG prompt builds to 10-15 K tokens and OOM-jetsams iPhone on prefill. Was the entire v9-v12 chat-crash class of bug. |
| `curatedToolsInChatLite` | ON | Exposes the top-3 chat-path tools (BreakDownScene, PickNextTask, RecallRelevantMemories) inside `chatLite` so Look / What Now / Recall fire without leaving the safe minimal-prompt path. |

For the demo build, verify both ON in Settings → Diagnostics → Flags
before recording. If either is OFF the demo breaks — `minimalChatPromptEnabled
OFF` crashes the app on first send, `curatedToolsInChatLite OFF`
silently degrades Look / What Now / Recall to generic chat replies.

**Historical note**: the old operational rule (pre-2026-05-19) said
"flip `minimalChatPromptEnabled` OFF for the demo so tool calling
works." That was wrong — it traded silent-tool-degradation for
guaranteed-OOM-crash. The structural fix moved curated tools and the
AuADHD essentials (grounding script, short-reply default, no-moralizing
rule) into the `chatLite` system prompt itself, so the safe path now
carries the demo flows. The old workaround is obsolete; do not apply
it. See `Eidos/RAG/RAGPipeline.swift::chatLite` for the expanded
prompt, `Eidos/App/AppContainer.swift` for the skill ordering, and
`Eidos/Platform/Diagnostics/EidosFeatureFlags.swift::curatedToolsInChatLite`
for the new default.

---

## Simulator vs device

- **Simulator (iOS)**: MLX Metal crashes. `GemmaSession.load()` /
  `generate()` use canned mock responses. Camera / mic return empty
  data. Useful for UI iteration only.
- **Mac (Designed for iPad)**: real MLX runtime, full Gemma pipeline.
  Used for development + benchmarking.
- **Physical iPhone (15 Pro+)**: real demo target. All sensors live.

When writing code that touches MLX, audio, camera, or other hardware
APIs, **always include a simulator mock path**.

---

## Commit + branch style

- **Branch**: `AuADHD` is the hackathon branch.
  `medical-helper` is the previous pivot (preserved).
  `main` is the historical Eidos product (preserved).
- **Commits**: imperative mood, one concern per commit.
  No mass-refactor commits — separate "move files" from "change
  behavior".
- **Line length**: soft 100, hard 120.
- **Indentation**: 4 spaces in Swift.
- **Commit messages carry the architectural rationale.** Be specific
  about why.

---

## Files Claude should read on session start

1. `PRODUCT.md` — product spec, current scope.
2. `CLAUDE.md` (this file) — working rules.
3. `README.md` — public-facing pitch + build instructions.
4. `project.yml` — xcodegen target/dependency config.
5. `Eidos/App/AppContainer.swift` — DI graph. The shape of the app is here.
6. `Eidos/Inference/GemmaSession.swift` — `runGuardedGeneration` is the
   only inference path; respect its invariants.
7. `Eidos/Inference/PromptTemplates.swift` — `systemPrompt`. AuADHD
   addendum lands here next session.

---

## End-of-session ritual

1. Update `PRODUCT.md` if scope or architecture changed.
2. Use a clear PR description for any merge into `AuADHD` — capture the
   *why*, not just the *what*.
