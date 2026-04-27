# CLAUDE.md — Instructions for Claude Code working on Eidos

> **Source of truth.** Read [`masterplan.md`](./masterplan.md) before making any design decision, adding any major feature, or pivoting architecture. If this file and `masterplan.md` ever disagree, `masterplan.md` wins and this file gets updated.

---

## On every turn, do this first

1. **Check `masterplan.md` first** — specifically the "Current State" table and the active phase's goals.
2. **If the user's ask touches a phase that's marked `DEFERRED`**, that's a signal it has upstream dependencies. Mention them before starting.
3. **If the user's ask introduces something not in the plan**, surface that — propose whether it belongs in the current phase, a later phase, or as a v2 feature. Update `masterplan.md` when the decision is made.
4. **Always cross-reference `KNOWN_LIMITATIONS.md`** before claiming a feature is broken — it may be a documented iOS-sandbox limit, not a bug.
5. **Every meaningful action gets a labeled log entry.** See "Logging discipline" below.

---

## Logging discipline (non-negotiable)

This project moves fast. Every developer-facing record — design decisions, ship deliverables, test reports, bugs caught, architectural invariants — must be **labeled, dated, and concise**. A new contributor reading the logs cold should be able to reconstruct the state of the project in 10 minutes. Treat the logs the way an office worker treats a labeled file folder: clear tabs on every document, no decoration, no decoration that isn't load-bearing information.

### Where things go

| File | Purpose | Append cadence |
|---|---|---|
| `developer_log.txt` | Per-version ship record. One entry per build sent to the tester. | Every IPA shipped. |
| `conversations/YYYY-MM-DD_<topic>.md` | Session record — decisions, dead ends, what was learned. | End of every meaningful Claude session. |
| `history.md` | Chronological turning points only — pivots, milestones, reversals. | Only when a turning point happens. |
| `masterplan.md` | Phase plan + Current State table. | When phase status changes or scope shifts. |
| `KNOWN_LIMITATIONS.md` | Things that intentionally don't work or can't work (iOS sandbox limits, etc.). | When a limitation is identified. |
| `architecture.md` | Component map + invariants. | When the architecture changes. |

### Label vocabulary

Every entry begins with a single bracketed label. Use them like file tabs.

| Label | Meaning |
|---|---|
| `[SHIP]` | An artifact (IPA, ZIP, doc) was produced and delivered. |
| `[DEV]` | Developer-side change (code, tooling, docs) not yet shipped. |
| `[TEST]` | Test result — manual on-device, smoke, unit, benchmark. |
| `[BUG]` | Reported defect; cite version + reproduction steps. |
| `[FIX]` | Defect remediation; cite which `[BUG]` it closes. |
| `[DECISION]` | Architectural or product choice that locks future work. |
| `[INVARIANT]` | Rule that future code must respect. Don't break without an `[INVARIANT-REVISED]`. |
| `[BLOCKER]` | Open issue blocking forward motion; cite owner + ETA if known. |
| `[RESEARCH]` | External-fact-finding result; cite sources. |
| `[REGRESSION]` | A previously-working feature broke. Cite the build that broke it + root cause. |
| `[DEFERRED]` | Work explicitly postponed; cite the gating dependency. |

### Format

- One blank line between entries.
- Entry header: `[LABEL] YYYY-MM-DD HH:MM — short title (under 60 chars)`.
- Body: 1–6 lines max. If it needs more, write a separate doc and link it.
- Cite versions with `vN` (e.g. `v12`).
- Cite files with relative path and identifier: `Eidos/Inference/GemmaSession.swift::runGuardedGeneration`.
- No emoji. No decorative dividers in entries (only between sections).
- ASCII-only body text. Use `—` only when copying from a quoted source.

### Example entry

```
[FIX] 2026-04-26 16:09 — v9 ships MLX cache discipline
Closes [BUG] v8 chat crash on second Gemma call per session.
Root cause: ModelContainer state-reuse on iPhone Metal.
Change: GemmaSession.clearMLXCache() called between every generation
(matches mlx-swift-lm BenchmarkHelpers practice).
Verification pending on-device.
```

### What NOT to log

- Step-by-step thinking ("I'm trying X, then Y, then Z"). Logs are decisions, not narration.
- Files modified — git captures that. Log the *why*.
- Generic praise or self-congratulation.
- Tool output that git or the build system already records.

### Discoverability

Every log file's first line points at the next-most-relevant file. A new contributor opening `developer_log.txt` should immediately see "for architectural invariants see CLAUDE.md", "for current scope see masterplan.md", etc.

---

## Engineering bar (non-negotiable)

These apply to every line of code written, regardless of which phase is active. Codified in `masterplan.md` §8.1 but restated here for quick access.

1. **Every public API has `///` doc comments.** Contributors read the file without asking.
2. **Every error path is a typed error.** No raw `NSError`. `errorDescription` is UI-ready.
3. **Swift 6 strict concurrency, zero warnings.** All shared state is actor-isolated, `Sendable`, or `@unchecked Sendable` with a comment explaining why.
4. **No force-unwraps, no `try!`, no `fatalError`** in production paths. Only in `#if DEBUG` assertions.
5. **Zero silent failures.** Every `catch { }` either logs or surfaces to the user.
6. **Crash-safe logging.** Logger writes on a background queue; logger failure never crashes the app.
7. **All metrics are machine-parseable.** JSONL with a stable schema.
8. **Unit tests for every tricky piece.** `EidosTests` target stays green on every commit.
9. **Fails-closed on safety.** Crisis / medical refusal paths are hardcoded string + regex, never reach the LLM. Unit-tested.
10. **Feature flags, not branches.** `EidosFeatureFlags` — toggleable without rebuild.

---

## Product principles

Locked decisions you don't re-open without checking with the user:

- **Zero egress after onboarding.** `EgressGuard` enforces this. Any new network call requires explicit approval + justification + a clear retention policy.
- **No telemetry, no analytics, no crash reporting to third parties.** Nothing phones home, ever.
- **On-device everything.** Inference, embeddings, STT, vision — all local. No exceptions for "just this one feature."
- **Privacy is the moat.** Feature decisions that weaken the privacy posture get pushed back, regardless of convenience.
- **Safety-critical paths never touch the LLM.** Crisis, medical, legal — hardcoded responses only.
- **Swift 6, iOS 26, SwiftData, MLX Swift.** Architecture locked.

## 🔥 Device-first mandate (non-negotiable)

**Every code decision must respect iPhone's physical envelope.** The app must not:

1. **Throttle the device.** Sustained Gemma loops → thermal → 10 %+ TPS drop. Read `ProcessInfo.thermalState` before heavy work. Honor `DeviceProfile.maxToolHops`, `DeviceProfile.contextBudgetChars`, `DeviceProfile.maxGenerationTokens`. Cap at `.serious`.
2. **Overheat.** Bursty inference — generate fast, return to idle. No continuous loops. `.thermalCritical` aborts generation mid-stream.
3. **Leak memory or crash.** Weak refs in `Task` closures. No retained streams. Monitor RSS via `MemoryProbe`.
4. **Degrade accuracy over time.** Per-session crystallization + periodic memory decay keep the context fresh. Avoid unbounded memory growth in-context; retrieval should use recency + priority rankings.
5. **Over-batch on main thread.** RAG retrieval, embedding, MD disk I/O → actors / background queues. UI is never blocked.

**Before shipping any new code that runs during generation or in a loop, verify:**
- [ ] Reads `DeviceProfile` to scale work by device class
- [ ] Has a `MemoryProbe.snapshot(tag:)` at entry + exit (DEBUG only)
- [ ] Respects the thermal guard (`GemmaError.thermalCritical` when appropriate)
- [ ] Has a feature flag (`EidosFeatureFlags`) if experimental
- [ ] Uses `async`/`await` — not `DispatchQueue.main.sync` ever
- [ ] Unit tests cover the "cold start" + "hot state" paths

**When Claude is adding new features:** default to iPhone-conservative. iPad/Mac can enjoy higher budgets; iPhone cannot. If a feature might hammer the GPU/ANE, it goes behind a feature flag, off by default on iPhone.

---

## Naming and legal discipline

- ❌ "Doctor" — legal minefield. Use: `Health Companion`.
- ❌ "Therapist" — same. Use: `Reflection Partner`.
- ❌ Clinical / prescriptive language in persona copy. No dosages, no diagnoses, no "you should take...".
- ❌ Never present LLM output as authoritative on medical, legal, or financial matters.
- ✅ Always include "consult a professional" disclaimers where the domain requires it.
- ✅ Surface grounding: "Based on what you told me on [date]" / "From your USDA nutrition corpus: ...".

---

## Current model: Gemma 4 E2B (multimodal)

- Path: `mlx-community/gemma-4-e2b-it-4bit`
- Size on disk: ~3.58 GB after 4-bit quantization
- Capabilities: text + image + audio input, text output, chain-of-thought
- Context window: 128 K tokens
- Apache 2.0 license (commercially usable)
- Swift packaging: upgrade to `MLXVLM` in Phase 8 (currently on `MLXLLM`, text-only path)

---

## Simulator vs device

- **Simulator (iOS or iPhone X+):** MLX Metal crashes in CoreAudio / Metal layer. Covered by `#if targetEnvironment(simulator)` mocks in:
  - `GemmaSession.load()` / `generate()` — canned responses
  - `SpeechTranscriber.start()` — canned transcript
  - `ModelDownloader.isModelDownloaded` — returns `true` to skip download screen
- **Mac (Designed for iPad):** runs the real arm64 iOS binary on the Mac's native GPU. MLX works fully. Used for development + benchmarking.
- **Physical iPhone:** real target. MLX + camera + mic all fully wired.

When writing new code that touches MLX, audio, camera, or other hardware-dependent APIs, **always include a simulator mock path**.

---

## Commit & code style

- **Branches:** feature/`<area>-<short-name>` (`feature/diagnostics-logger`)
- **Commits:** imperative mood, one concern per commit (`Add EidosLogger with JSONL persistence`)
- **No mass-refactor commits.** Separate "move files" from "change behavior".
- **PRs:** every PR links to the masterplan section it addresses.
- **Line length:** soft 100, hard 120.
- **Indentation:** 4 spaces in Swift (Apple-standard).

---

## Tests

- **`EidosTests`** target — all unit tests live here.
- **Coverage target:** 70% overall, 95% on safety gates, persona routing, logger, memory crystallization.
- **Run before every commit:** `⌘U` in Xcode, or `xcodebuild test -scheme Eidos -destination 'platform=iOS Simulator,name=iPhone 17'`.
- **Benchmark corpus** (Phase 8) is not a unit test — it's a nightly / pre-release gate.

---

## Diagnostics (dev mode)

- All logs persist to `~/Documents/eidos/logs/YYYY-MM-DD.jsonl` (never rotated — keep all).
- Settings → Diagnostics shows live log tail, metrics table, and "Run Benchmarks" button.
- `DEBUG` builds have Diagnostics always visible; `RELEASE` builds hide it behind 5-taps-on-version-number.

---

## Files Claude should read when picking up a session

If starting fresh, these are the canonical context sources in priority order:

1. `masterplan.md` — phase plan, current state, design decisions
2. `CLAUDE.md` (this file) — working rules
3. `history.md` — chronological turning points
4. `conversations/` — full session records for each meaningful Claude session. Read the newest first. When this session ends, write a session log here under `YYYY-MM-DD_<topic>.md`.
5. `KNOWN_LIMITATIONS.md` — what's intentionally not supported
6. `architecture.md` — component map
7. `SHORTCUTS.md` — App Intent catalogue for the Shortcuts app
8. `README.md` — public-facing overview
9. `project.yml` — xcodegen target/dependency config

---

## When the user pivots

If the user asks for a feature or change that doesn't fit the current phase:

1. Restate the ask in one sentence.
2. Identify where it lives in the plan (existing phase / new phase / post-launch).
3. Flag dependencies and trade-offs.
4. Propose: "do this now (reprioritize)", "queue it for Phase N", or "ship v1 without it".
5. If agreed, **update `masterplan.md` immediately** — don't let the plan drift.

---

## Current active work

See `masterplan.md` "Current State" table. As of 2026-04-23: **Phase 8 — Multimodal + Observability** (85% complete). Remaining: MLXVLM swap, ChatInputBar multimodal wiring, long-context packing, vision/audio rubrics, additional unit tests.

Execution queue in the "Timeline Priority" section of the masterplan.

Latest session record: [`conversations/2026-04-23_phase8_multimodal_observability.md`](conversations/2026-04-23_phase8_multimodal_observability.md).

---

## End-of-session ritual

Before concluding any meaningful session:

1. **Update `masterplan.md`** if architecture or plan changed.
2. **Write a session record** in `conversations/YYYY-MM-DD_<topic>.md` — decisions, open items, what's next.
3. **Append to `history.md`** if a meaningful turning point happened (not every session warrants a history entry).
4. **Update the Current State table** in `masterplan.md` if a phase's status changed.
