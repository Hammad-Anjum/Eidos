# Eidos — Product Spec (AuADHD Companion, Hackathon Submission)

> Source of truth. If this file and the code disagree, this file
> wins until updated. **Last updated**: 2026-05-14 (RAG hotfix
> commit `ea48a66`; Phase 1–3.5 complete; 4 days to submission).

## What this is

An on-device AuDHD companion for the **Kaggle Gemma 4 Good Hackathon**
(deadline 2026-05-18). Eidos lives entirely on the user's iPhone via
Gemma 4 E2B on MLX Swift, with **zero network egress** after the
one-time model download. It surfaces four flows shaped to AuDHD
(autism + ADHD overlap) executive function:

1. **Look** — photo of a cluttered scene → spoken 3-step plan.
2. **Ground** — voice in during RSD or sensory overwhelm → scripted
   grounding response, never a follow-up question.
3. **Journal** — mic → ramble → memory entries tagged for recall.
4. **What Now** — voice "I have N things and my brain stopped" → 1
   task + a 5-minute commitment script.

Plus a system-prompt section that defaults the entire assistant to a
**low-friction, inertia-aware tone** — short replies, one option, no
moralizing, no streaks.

## User

AuDHD adults, with the underserved sub-segments the existing
ADHD/autism app market has failed:

- **Late-diagnosed autistic adults**, especially women, who realized
  they were on the spectrum in adulthood and are navigating identity
  + burnout in a market full of cloud-based wellness apps.
- **Post-burnout** AuDHD adults for whom existing apps demand the
  executive function they currently don't have (54% drop within weeks
  per RevenueCat / Wellnest research).
- **Users who refuse cloud mental-health data**. Data brokers
  actively sell ADHD / depression / autism diagnosis lists; insurance
  underwriters use them. Most existing AI ADHD tools (Goblin Tools,
  Saner.AI, Inflow's coach side, Tiimo's Co-planner) route through
  cloud LLMs.

## Core flow

```
Home → 4 voice-first tiles → matched on-device flow

  Look    →  camera  →  Gemma 4 vision  →  spoken plan
  Ground  →  voice   →  Gemma scripted   →  spoken 5-4-3-2-1 + breath
  Journal →  mic     →  crystallizer     →  tagged memory + recall
  What Now → voice   →  energy + memory + calendar → 1 task + script
```

The full demo loop is 30 seconds on screen. Multimodal in, function
calling out, real-world action visible, all on-device.

## Surfaces

### Skills (3) — ✅ shipped (commit `eede6ee`)

| Skill | Input | Output |
|---|---|---|
| `BreakDownSceneSkill` | image (photo of scene) | spoken 3-step plan, ~5 min total commitment |
| `VoiceJournalCaptureSkill` | transcribed voice | verbatim `MemoryEntry` (`.recentSession`, P3, tags `journal` + `journal-YYYY-MM-DD`). Crystallizer deliberately skipped in v1 to preserve user's words exactly; recovery file written to `/tmp/journal-recovery/` on save failure. |
| `PickNextTaskSkill` | (energy level, calendar, memory) | 1 task + 5-min commitment script |

### Chat tools (1) — ✅ shipped (commit `eede6ee`)

| Tool | Input | Output |
|---|---|---|
| `recall_relevant_memories` | query string | top 3 semantically-similar past memory entries (via `MemoryRecallService.recall`) |

### Recall coverage (RAG hotfix — commit `ea48a66`)

Two paths feed every chat turn's memory context:

- **`MemoryRecallService.indexEntry` fires automatically** on every
  `MemoryManager.save()` via the `onSave` hook attached in
  `AppContainer.bootstrap()`. New journal entries are findable on
  the SAME turn — no app-relaunch required. `touch()` suppresses
  the hook (no embed-source change).
- **`ContextBuilder.build(query:)` merges rule-based + semantic
  recall.** Rule-based: P1 + activePriorities + topK hot topic.
  Semantic: cosine ≥ 0.40. The merge lets `.recentSession`
  entries reach the prompt even when the rule-based pass would
  exclude them.

### Prompt sections (2) — ✅ shipped in `PromptTemplates.systemPrompt`

- **Inertia-default tone** — short replies, one option, slow pacing,
  no "should/ought/need to" language. Hyperfocus-mode hyperinterrupt
  pattern is v2.
- **Grounding (RSD / overstim)** — full deterministic script section.
  Trigger phrases: "spiraling", "can't think", "want to quit",
  "got criticized", "everything is loud", "RSD". Response shape:
  acknowledge (1 sentence) → 5-4-3-2-1 sensory cue → breath cue
  (in-4 hold-2 out-6, twice) → ONE physical action. End. No follow-up
  question.

### Settings toggles

- **Audience mode**: deferred to v2. v1 ships AuDHD-default only.
- **Speak replies aloud**: `EidosFeatureFlags.shared.speakRepliesEnabled`.
- **Energy level slider**: 0-4, persisted via `@AppStorage("eidos.auadhd.energyLevel")`,
  injected into the `pick_next_task` prompt and read by the skill as fallback.
  Spoons-style minimal UX.
- **Repeat last utterance** (Phase 3.5): per-bubble speaker button in
  chat + global `SpeechSynthesizer.shared.repeatLast()`.

### Onboarding (Phase 3.5 — commit `72ec6e8`)

5-step flow, all skippable except the model download:

1. **Welcome** — single CTA + tiny "Skip the tour" escape hatch.
2. **How Eidos is different** — 3 audience-anchored cards
   (privacy, no streaks/shame, two taps to skip).
3. **Choose your model** — Gemma 4 E2B (default) / E4B (15 Pro+).
4. **IdentityStep** — preferred name + purpose category (5 presets
   + "in my own words"). Both optional. Seeds:
   - Name → `UserDefaults` (`eidos.user.displayName`).
   - Purpose → P1 `MemoryEntry` in `.coreIdentity` tier (auto-indexed
     into recall via the `onSave` hook).
5. **Model download** — the only un-skippable step.

### Home (Phase 3 — commit `be14a84`)

- 2×2 voice-first tile grid: Look / Ground / Journal / What Now.
  Min 130pt tiles (≈3× HIG minimum) for motor-tremor users.
- Spoons-style energy slider (0–4) above tiles.
- "I need help now" crisis bar below tiles — opens
  `CrisisResourcesView` directly (988 / 911 / Crisis Text /
  grounding). Bypasses chat entirely; no Gemma involved.
- Tile dispatch via `AppContainer.pendingChatLaunch: ChatLaunchIntent?`
  drained by `ChatView.onChange`. Journal is the one exception —
  presents a full-screen `JournalRecordingView` that calls
  `VoiceJournalCaptureSkill` imperatively.
- Time-of-day softly-changing gradient background.

### Surfaces explicitly NOT in v1

- Scripting / "draft 3 versions" — tonally collides with grounding;
  reserved for v2.
- Hyperfocus-mode interrupt — v2 (validates with real users first).
- Transition warnings via BGTask — iOS scheduling unreliable; reserved
  for v2.
- HealthKit biofeedback / sensory regulation — reserved for v2.
- AI body doubling — reserved for v2.
- Late-diagnosed onboarding self-discovery flow — reserved for v2.

## What this app explicitly is not

- **Not a therapist, not a coach, not a productivity tool**. It's a
  pocket presence.
- **Not a diagnostic tool**. Self-identification only; no inference
  of neurotype.
- **Not gamified**. No streaks, no badges, no pet that dies if you
  miss a day. (Existing market well-served by Finch; we're not that.)
- **Not a planner**. Tiimo is excellent at planning; we don't compete
  there. We compete for the moments when planning has already failed.

## Engineering invariants (carried over)

These survived the v3-v12 chat-stability marathon. **Must not be
relaxed in this pivot.**

1. `runGuardedGeneration()` is the only path that calls Gemma. FIFO
   lock + MLX cache clear + thermal abort + memory pre-flight live
   there once.
2. `MLX.Memory.clearCache()` between every generation on iPhone.
3. Every TCC permission callback is `@Sendable`.
4. `AVAudioSession` `.record` pairs with `.measurement` mode.
5. ChatViewModel throttles streaming UI updates to ~60 ms.
6. Pre-flight memory check before any prefill —
   `GemmaError.memoryConstrained` if below threshold.
7. Diagnostics → Smoke pane is the regression baseline.
8. `RAGPipeline.chat` is single-tool-loop. No chaining.

## Critical demo-day gotcha

`EidosFeatureFlags.shared.minimalChatPromptEnabled` **defaults ON on
iPhone Release** to keep prefill inside Metal's heap budget. When ON,
the chat path bypasses tool catalogue — Gemma will not call
`BreakDownSceneSkill` or `PickNextTaskSkill`. **Flip OFF on the demo
build via Settings → Diagnostics → Flags**, verify a test tool call
fires, THEN record.

## Roadmap (post-hackathon)

- Hyperfocus-mode interrupt with HRV signal (gap 5 from research).
- Sensory-regulation biofeedback via HealthKit HRV (gap 7).
- BGTask transition warnings if Apple's BGAppRefreshTask reliability
  improves (gap 9).
- AI body doubling — voice-first Focusmate-style sessions, no human
  on camera (gap 11).
- Late-diagnosed adult onboarding — voice-led "tell me about your day"
  pattern surfacing (gap 12).
- Per-context masking / scripting — draft 3 tonal variants of a
  message (gap 4); deferred because it tonally collides with grounding.

## Compressed timeline (as of 2026-05-14)

The 19-day timeline was set on 2026-04-29 and burned. Canonical
playbook is now `NEXT_PHASES.md`. Current state:

| Phase | Status | Commit |
|---|---|---|
| Branch cut + docs reframe | ✅ | `b477741` → `eede6ee` |
| Skills + prompt addendum + bench fixtures | ✅ | `eede6ee` |
| Home UX (tiles + energy + journal mic) | ✅ | `be14a84` |
| Phase 3.5 (speaker button, crisis tile, onboarding refresh, IdentityStep) | ✅ | `72ec6e8` |
| RAG hotfix (auto-index + semantic merge) | ✅ | `ea48a66` |
| Mac build verify + reliability sweep | ⬜ blocker | — |
| Demo shoot + tcpdump + write-up + submit | ⬜ | — |

**4 days left.** Hard deadline 2026-05-18 23:59 UTC.

## Submission deliverables (Kaggle)

- [ ] Working demo (TestFlight or buildable repo).
- [ ] Public code repo (this branch, made public on submission day).
- [ ] Technical write-up (~2 pages).
- [ ] 3-minute demo video filmed against the script in `plans/...`.
- [ ] Honest accuracy table per surface (BenchmarkRunner output).
