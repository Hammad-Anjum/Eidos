# CLAUDE.md — Working rules for Claude Code on Eidos Android

> **Source of truth.** Read [`plan.md`](./plan.md) before making any design decision, adding any major feature, or pivoting architecture. If this file and `plan.md` ever disagree, `plan.md` wins and this file gets updated.

---

## On every turn, do this first

1. **Check `plan.md` first** — specifically the **Current State** table and the active phase's goals.
2. **If the user's ask touches a phase marked deferred**, surface that — upstream dependencies may apply. Flag it before starting.
3. **If the user's ask introduces something not in the plan**, propose where it belongs (current phase / later phase / post-hackathon) and update `plan.md` when the decision is made.
4. **Always read `docs/android-notes.md`** before claiming a feature is broken — it may be a documented Android/OEM limitation, not a bug.

---

## Hackathon context (do not relitigate)

This project targets the **Google Gemma 4 for Good Hackathon**. Two hard constraints:

- **Google's Gemma stack only.** Inference runs via **LiteRT-LM (Google AI Edge)**. Do not propose llama.cpp, MLC-LLM, ONNX LLM runtimes, or any other inference backend. The hackathon judges on Google-stack alignment.
- **Model: Gemma 4 E2B** (`.task` bundle, multimodal). E4B is in scope later if device-class permits, but E2B is the default.

If a limitation in LiteRT-LM appears to block progress, the answer is **work around it**, not swap the runtime. Escalate to user before touching the inference layer.

---

## Engineering bar (non-negotiable)

Applies to every line of code, regardless of phase. Codified in `plan.md` but restated here for quick access.

1. **Public APIs have KDoc.** Contributors read the file without asking.
2. **Typed errors via sealed classes.** No raw `Exception` / `RuntimeException` at boundaries. Error messages are UI-ready.
3. **Kotlin structured concurrency.** Every coroutine has a scope. `viewModelScope` / `lifecycleScope` / explicit `CoroutineScope` — never `GlobalScope`. Never leak jobs.
4. **No `!!`, no `lateinit` on release paths, no `fatalError`** equivalents. `check(...)` / `require(...)` only in DEBUG-gated paths.
5. **Zero silent `catch`.** Every handler either logs via `EidosLogger` or surfaces to the user via typed error.
6. **Crash-safe logging.** `EidosLogger` writes on `Dispatchers.IO` with best-effort flush; logger failure never crashes the app.
7. **Metrics are JSONL, stable schema.** Define schema once, never break it silently.
8. **Unit tests for every tricky piece.** `test/` stays green on every commit. `androidTest/` runs on the self-hosted runner.
9. **Fails-closed on safety.** Crisis / medical / dosing / diagnosis / legal / child-safety paths are hardcoded regex + responses, never reach the LLM. Unit-tested against a crisis-phrase corpus.
10. **Feature flags, not branches.** `EidosFeatureFlags` — DataStore-backed, toggleable without rebuild. No `#ifdef`-equivalent branching.

---

## Product principles (locked)

Do not re-open without checking with the user:

- **Zero egress after onboarding.** `EgressGuard` (NetworkSecurityConfig + OkHttp `CertificatePinner`) enforces this. Any new network call requires explicit user approval + justification + a retention policy.
- **No telemetry, no analytics, no crash reporting to third parties.** Nothing phones home, ever. No Firebase, no Crashlytics, no Google Analytics, no Play Integrity API calls.
- **On-device everything.** Inference, embeddings, STT, vision — all local. No "just this one feature" exceptions.
- **Privacy is the moat.** Feature decisions that weaken the privacy posture get pushed back regardless of convenience.
- **Safety-critical paths never touch the LLM.** Crisis, medical, legal → hardcoded responses only.
- **Kotlin 2.x, Android 14 (target 15), Compose, Room, LiteRT-LM.** Architecture locked.

---

## 🔥 Device-first mandate (non-negotiable)

**Every code decision must respect the phone's physical envelope.** The app must not:

1. **Throttle the device.** Sustained Gemma loops → thermal → >10% tok/s drop. Read `PowerManager.currentThermalStatus` before heavy work. Honor `DeviceProfile.maxToolHops`, `DeviceProfile.contextBudgetChars`, `DeviceProfile.maxGenerationTokens`. Cap at `THERMAL_STATUS_SEVERE`.
2. **Overheat.** Bursty inference — generate fast, return to idle. No continuous loops. `THERMAL_STATUS_CRITICAL` aborts generation mid-stream.
3. **Leak memory or crash.** Weak refs in coroutine closures where appropriate. No retained streams. Monitor heap via `Debug.MemoryInfo` / `Runtime.totalMemory()`.
4. **Degrade accuracy over time.** Per-session crystallization + periodic memory decay keep context fresh. Avoid unbounded memory growth in-prompt; retrieval uses recency + priority.
5. **Block the main thread.** RAG retrieval, embedding, Room I/O → `Dispatchers.IO`. UI is never blocked.

**Before shipping any code that runs during generation or in a loop, verify:**

- [ ] Reads `DeviceProfile` to scale work by device class
- [ ] Has a `MemoryProbe.snapshot(tag)` at entry + exit (DEBUG only)
- [ ] Respects the thermal guard (`GemmaError.ThermalCritical` or equivalent)
- [ ] Has a feature flag (`EidosFeatureFlags`) if experimental
- [ ] Uses `suspend` + `Dispatchers.IO` — never blocks the main thread
- [ ] Unit tests cover the cold-start + hot-state paths

**Default to conservative budgets.** Flagships get higher caps; mid-range does not. Any feature that hammers the GPU/NPU goes behind a feature flag, off by default.

---

## OEM survival notes

Android isn't iOS — battery optimization on Samsung (One UI), Xiaomi (MIUI), OPPO/OnePlus (ColorOS/OxygenOS), and Huawei (EMUI) is aggressive and will silently kill:

- **WorkManager periodic jobs** — Doze + App Standby Buckets delay them indefinitely. For time-critical triggers (morning digest), use `AlarmManager.setExactAndAllowWhileIdle` to fire the worker, not a plain `PeriodicWorkRequest`.
- **ForegroundService** — even with `foregroundServiceType=dataSync`, OEMs drop it if the user doesn't grant battery exception.
- **NotificationListenerService** — Android 13+ requires "Restricted Settings" toggle; Android 14+ tightens further. Onboarding must teach this.

Onboarding flow must deep-link to the OEM's battery exception screen with clear copy per vendor. See `docs/android-notes.md` (created in A0.5) for the deep-link table.

---

## Naming and legal discipline

- ❌ **"Doctor"** — legal minefield. Use: **Health Companion**.
- ❌ **"Therapist"** — same. Use: **Reflection Partner**.
- ❌ Clinical / prescriptive language. No dosages, no diagnoses, no "you should take...".
- ❌ Never present LLM output as authoritative on medical, legal, or financial matters.
- ✅ Always include "consult a professional" disclaimers where the domain requires it.
- ✅ Surface grounding: "Based on what you told me on [date]" / "From your USDA nutrition corpus: ...".

---

## Current model: Gemma 4 E2B (multimodal)

- Hugging Face: `google/gemma-4-e2b-it` (E2B instruction-tuned) — LiteRT `.task` bundle
- Size on disk: ~3.58 GB after 4-bit quantization
- Capabilities: text + image + audio input; text output; chain-of-thought
- Context window: 128 K tokens
- License: Apache 2.0 (commercially usable)
- Runtime: **LiteRT-LM (Google AI Edge)** — Kotlin binding, native multimodal support

---

## Emulator vs device

- **Android emulator** (RDC + GTX 1660 host): fine for Compose UI work, Room / WorkManager / permission flows, JVM + instrumented tests. **Inference benchmarks are meaningless on an emulator** — x86_64 CPU path is nothing like ARM NPU.
- **Real device** required for Phase A2 milestone onwards. Minimum: Pixel 7+, Galaxy S22+, or equivalent Snapdragon 8 Gen 2+ / Tensor G2+ with 8 GB RAM.
- **Desktop Gemma sandbox on the RDC**: Google AI Edge has desktop builds. Useful for prompt iteration without Android rebuild cycles. Does not replace on-device validation.

When writing code that touches LiteRT-LM, camera, audio, or hardware-dependent APIs, always include a **fake/mock path** for emulator + JVM unit tests.

---

## Commit + code style

- **Branches**: `feature/<area>-<short>` — e.g. `feature/diagnostics-logger`, `feature/a2-litert-bringup`
- **Commits**: imperative mood, one concern per commit — e.g. `Add EidosLogger with JSONL persistence`
- **No mass-refactor commits.** Separate "move files" from "change behavior".
- **PRs**: every PR links to the `plan.md` phase it addresses
- **Line length**: soft 100, hard 120
- **Indentation**: 4 spaces (Kotlin convention)
- **Package**: `com.hissamuddin.eidos`
- **File naming**: Kotlin PascalCase class files. One public top-level declaration per file unless tightly-coupled helpers.
- **KDoc on every public declaration.**

---

## Tests

- **JVM unit tests** in `app/src/test/` — for pure logic (SafetyGate, TextChunker, VectorStore, RRF, PromptTemplates, MemoryCrystallizer, SkillParser)
- **Instrumented tests** in `app/src/androidTest/` — for Room, WorkManager, permission flows, Intent routing
- **Compose UI tests** — for Chat, Onboarding, Diagnostics critical paths
- **Coverage target**: 70% overall, 95% on safety gate + skills + memory crystallization
- **Run before every commit**: `./gradlew test` on the RDC
- **Benchmark corpus** is not a unit test — nightly / pre-submission gate on real device

---

## Diagnostics (dev mode)

- Logs persist to `filesDir/eidos/logs/YYYY-MM-DD.jsonl` — never rotated, keep all
- Settings → Diagnostics shows live log tail, metrics table, and "Run Benchmarks" button
- DEBUG builds: Diagnostics always visible
- RELEASE builds: hidden behind 5-taps-on-version-number

---

## Files Claude should read when picking up a session

In priority order:

1. [`plan.md`](./plan.md) — phase plan, current state, design decisions
2. [`CLAUDE.md`](./CLAUDE.md) (this file) — working rules
3. [`docs/sessions/`](./docs/sessions/) — full session records, newest first. Write a new one when this session ends.
4. [`docs/android-notes.md`](./docs/android-notes.md) — OEM quirks and Android-specific gotchas (created in A0.5)
5. Recent `git log --oneline -20`
6. `AndroidManifest.xml`, `settings.gradle.kts`, `app/build.gradle.kts` for current module layout

---

## When the user pivots

If the user asks for a feature that doesn't fit the current phase:

1. Restate the ask in one sentence.
2. Identify where it lives in the plan (existing phase / new phase / post-hackathon).
3. Flag dependencies and trade-offs.
4. Propose: "do this now (reprioritize)", "queue it for Phase AN", or "ship v1 without it".
5. If agreed, **update `plan.md` immediately** — don't let the plan drift.

---

## Hackathon-specific discipline

- **Scope creep is the enemy.** v1 Android-exclusive features are hard-locked to NotificationListener + Share + toggled ForegroundService. AccessibilityService stays deferred.
- **Multimodal is the demo.** A2 wires text + image + audio from day one because that's what judges score on.
- **The "for good" narrative** (zero-egress, on-device, no telemetry) is central. Anything that weakens it weakens the submission.
- **A9 is not optional.** Submission polish (README, demo video, signed APK, judge-facing doc) is a real phase, not decorative.

---

## End-of-session ritual

Before concluding any meaningful session:

1. **Update `plan.md` Current State table** if a phase's status changed
2. **Write a session record** in `docs/sessions/YYYY-MM-DD_<topic>.md` — decisions, open items, what's next
3. **Commit** with an imperative-mood message; one concern per commit
4. **Push** to origin (the user will configure the remote; do not assume it's set up)

---

## Environment quirks

- **Primary dev**: Windows 11 via RDC to gaming PC (GTX 1660). Bash shell available (use Unix-style paths). PowerShell also available.
- **Build machine**: same Windows RDC — Android Studio + Gradle.
- **Real device**: TBD (user will plug in when A2 lands).
- **Keystore**: generate once, back up out-of-band to password manager + encrypted drive. Losing it = cannot update the app.
- **Never commit**: `*.keystore`, `*.jks`, `keystore.properties`, `local.properties`, `google-services.json`, `.env*`.
