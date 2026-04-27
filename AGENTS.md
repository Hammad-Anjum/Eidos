# AGENTS.md — Instructions for Codex working on Eidos

> **Source of truth.** Read [`masterplan.md`](./masterplan.md) before making any design decision, adding any major feature, or pivoting architecture. If this file and `masterplan.md` ever disagree, `masterplan.md` wins and this file gets updated.

---

## On every turn, do this first

1. **Check `masterplan.md` first** — specifically the "Current State" table and the active phase's goals.
2. **If the user's ask touches a phase that's marked `DEFERRED`**, that's a signal it has upstream dependencies. Mention them before starting.
3. **If the user's ask introduces something not in the plan**, surface that — propose whether it belongs in the current phase, a later phase, or as a v2 feature. Update `masterplan.md` when the decision is made.
4. **Always cross-reference `KNOWN_LIMITATIONS.md`** before claiming a feature is broken — it may be a documented iOS-sandbox limit, not a bug.

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

**When Codex is adding new features:** default to iPhone-conservative. iPad/Mac can enjoy higher budgets; iPhone cannot. If a feature might hammer the GPU/ANE, it goes behind a feature flag, off by default on iPhone.

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
- Capabilities: text + image input today, local speech-to-text voice input, text output, chain-of-thought. Native raw-audio attachments are wired in Eidos but blocked on the current `mlx-swift-lm` public API.
- Context window: 128 K tokens
- Apache 2.0 license (commercially usable)
- Swift packaging: `MLXVLM` image path is wired. `MLXLLM` remains available for text-only paths.

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

## Files Codex should read when picking up a session

If starting fresh, these are the canonical context sources in priority order:

1. `masterplan.md` — phase plan, current state, design decisions
2. `AGENTS.md` (this file) — working rules
3. `history.md` — chronological turning points
4. `conversations/` — full session records for each meaningful Codex session. Read the newest first. When this session ends, write a session log here under `YYYY-MM-DD_<topic>.md`.
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

See `masterplan.md` "Current State" table. As of 2026-04-25: **Phase 8 — Multimodal + Observability** is complete. Current active work is real-device validation, then Phase 9 — Skills / Personas.

Execution queue in the "Timeline Priority" section of the masterplan.

Latest session record: [`conversations/2026-04-26_altstore_first_launch_crash.md`](conversations/2026-04-26_altstore_first_launch_crash.md).

---

## End-of-session ritual

Before concluding any meaningful session:

1. **Update `masterplan.md`** if architecture or plan changed.
2. **Write a session record** in `conversations/YYYY-MM-DD_<topic>.md` — decisions, open items, what's next.
3. **Append to `history.md`** if a meaningful turning point happened (not every session warrants a history entry).
4. **Update the Current State table** in `masterplan.md` if a phase's status changed.
