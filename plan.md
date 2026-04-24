# Eidos Android — Build Plan

> **Source of truth.** Any design decision, new module, or pivot gets reconciled against this file. Code commits that introduce new architecture update this doc in the same commit. If `CLAUDE.md` and this file conflict, this file wins.

---

## Vision

An on-device Android AI personal assistant that **remembers, acts, sees, hears, and stays private**. Gemma 4 runs locally via Google AI Edge (LiteRT-LM). Every byte of user data stays on the device after the one-time model download. Zero telemetry, zero analytics, zero crash reporting to third parties.

Built for the **Google Gemma 4 for Good Hackathon**.

---

## Current State

| Phase | Status |
|---|---|
| Pre-work — clean slate + repo init | ✅ done |
| A0 — Gradle scaffolding + observability foundation | 🚧 next |
| A0.5 — OEM survival kit + policy foundation | ⏳ pending |
| A1 — Persistence + embeddings | ⏳ pending |
| A2 — LiteRT-LM inference bring-up (multimodal) | ⏳ pending |
| A3 — Memory + RAG + tool loop | ⏳ pending |
| A4a — Platform data sources | ⏳ pending |
| A4b — Skills + home | ⏳ pending |
| A5 — Ingestion + share | ⏳ pending |
| A6 — Proactive + notifications + widget | ⏳ pending |
| A7 — Safety + zero-egress demo | ⏳ pending |
| A8 — Android-exclusive unlock (minimal scope) | ⏳ pending |
| A9 — Hackathon submission polish | ⏳ pending |

---

## Locked decisions

| Topic | Choice |
|---|---|
| Language | Kotlin 2.x + coroutines + Flow |
| UI | Jetpack Compose + Material 3 |
| Persistence | Room + DataStore |
| **Inference** | **LiteRT-LM (Google AI Edge), Kotlin binding.** Hackathon mandates Google's stack. No alternatives. |
| Model | Gemma 4 E2B `.task` bundle (~3.58 GB, 4-bit quantized, multimodal) |
| Embeddings | MediaPipe TextEmbedder primary; ONNX Runtime + all-MiniLM-L6-v2 as fallback if coverage lacking |
| Vector store | sqlite-vec extension on Room's SQLite (16-KB page-aligned) |
| Min SDK | 31 (Android 12) |
| Target SDK | 35 (Android 15) |
| ABI | arm64-v8a only |
| Distribution | TBD (Play Store vs sideload) — decided during A8 |
| Repo | Single GitHub repo, single `main` branch (Android-only) |

---

## Non-negotiable product principles

1. **Zero egress after onboarding.** `EgressGuard` (NetworkSecurityConfig + OkHttp `CertificatePinner`) blocks all outbound traffic except the Hugging Face model-download window.
2. **No telemetry, no analytics, no crash reporting** to third parties. Ever.
3. **On-device everything** — inference, embeddings, STT, vision.
4. **Privacy is the moat.** Feature decisions that weaken privacy get pushed back regardless of convenience.
5. **Safety-critical paths never touch the LLM.** Crisis / medical / legal → hardcoded refusal via `SafetyGate`. Unit-tested against a curated crisis-phrase corpus.
6. **Gemma 4 via LiteRT-LM — hackathon-locked.** Do not propose alternative runtimes.

---

## Engineering bar (non-negotiable)

Applies to every line of code.

1. **Public APIs have KDoc.** Contributors read the file without asking.
2. **Typed errors via sealed classes.** No raw `Exception` / `RuntimeException` at boundaries.
3. **Kotlin structured concurrency.** Every coroutine has a scope. Never leak jobs.
4. **No `!!`, no `lateinit` on release paths, no crashes** in production flows.
5. **Zero silent `catch`.** Every handler logs or surfaces to the user.
6. **Crash-safe logging.** `EidosLogger` writes on `Dispatchers.IO`; logger failure never crashes the app.
7. **Metrics are JSONL, stable schema.**
8. **Unit tests for every tricky piece.** JVM unit tests in `test/`, instrumented in `androidTest/`. Coverage targets: 70% overall, 95% on SafetyGate + skills + memory crystallization.
9. **Fails-closed on safety.** SafetyGate regex + hardcoded responses. Tested.
10. **Feature flags, not branches.** `EidosFeatureFlags` — DataStore-backed, toggleable in Diagnostics. Never branch compilation.

---

## Device-first mandate

Every new code path that runs during generation or in a loop verifies:

- [ ] Reads `DeviceProfile` (RAM, CPU cores, thermal status via `PowerManager.ThermalStatusListener`)
- [ ] Has a `MemoryProbe.snapshot(tag)` at entry + exit (DEBUG only)
- [ ] Respects the thermal guard — aborts at `THERMAL_STATUS_SEVERE`
- [ ] Has a feature flag in `EidosFeatureFlags` if experimental
- [ ] Uses `suspend` / `Dispatchers.IO` — never blocks the main thread
- [ ] Unit tests cover cold-start and hot-state paths

OEM reality: Samsung/Xiaomi/OPPO aggressively kill background work. Every `ForegroundService` or `WorkManager` job must account for Doze + battery-exception UX. See `docs/android-notes.md` for OEM deep-link table (created in A0.5).

---

## Naming / legal discipline

- ❌ "Doctor" — legal minefield. Use: **Health Companion**.
- ❌ "Therapist" — same. Use: **Reflection Partner**.
- ❌ Clinical / prescriptive language in persona copy. No dosages, no diagnoses, no "you should take...".
- ❌ Never present LLM output as authoritative on medical, legal, or financial matters.
- ✅ Always include "consult a professional" disclaimers where the domain requires it.
- ✅ Surface grounding: "Based on what you told me on [date]" / "From your USDA nutrition corpus: ...".

---

## Target stack

| Layer | Choice |
|---|---|
| Calendar / Reminders | `CalendarContract` — Android has no separate Reminders DB |
| Contacts | `ContactsContract` |
| Health | Health Connect (Jetpack), graceful-degrade on Android <14 |
| Location / Motion | `FusedLocationProviderClient`, `ActivityRecognitionClient` |
| Music | `MediaStore` |
| Audio capture | `AudioRecord` → Int16 PCM (Gemma 4 native audio path) |
| Speech fallback | Android `SpeechRecognizer` (on-device where supported), thermal-throttle only |
| Camera | CameraX + Photo Picker |
| Notifications | NotificationManager + AlarmManager (exact) + WorkManager (deferrable) |
| Widgets | Glance (Compose-based) |
| App Intents | App Shortcuts + App Actions (Assistant) |
| Share | `ShareReceiverActivity` (`ACTION_SEND` intent filter) |
| Encrypted storage | `EncryptedSharedPreferences` + `EncryptedFile` (AndroidX Security) |
| Network egress control | NetworkSecurityConfig + OkHttp `CertificatePinner` + optional `VpnService` audit |

---

## Module layout

```
/                                 (repo root, Android Gradle project)
├── .gitignore
├── plan.md                       (this file — source of truth)
├── CLAUDE.md                     (working rules for Claude sessions)
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
├── gradle/libs.versions.toml     (version catalog)
├── app/
│   ├── build.gradle.kts
│   ├── proguard-rules.pro
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   ├── kotlin/com/hissamuddin/eidos/
│       │   │   ├── App.kt                           (Application + DI root)
│       │   │   ├── inference/                       (GemmaSession, ModelDownloader, PromptTemplates, ReasoningMode)
│       │   │   ├── embedding/                       (EmbeddingService, VectorStore)
│       │   │   ├── knowledgebase/                   (Room entities, DAOs, repository, TextChunker)
│       │   │   ├── rag/                             (RAGPipeline, ContextBuilder)
│       │   │   ├── skills/                          (SkillRegistry, SkillParser, + builtin/*)
│       │   │   ├── memory/                          (MemoryManager, Crystallizer, DecayEngine, Index, Exporter, Frontmatter, Aggregator)
│       │   │   ├── platform/                        (DeviceProfile, EgressGuard, SafetyGate, data sources, capture services, diagnostics)
│       │   │   ├── ingestion/                       (IngestionCoordinator, WhatsApp/Mail/PlainText importers)
│       │   │   ├── digest/                          (DigestGenerator, ProactiveDigestWorker)
│       │   │   ├── ui/                              (Compose screens: chat, home, memory, kb, onboarding, settings, components, theme)
│       │   │   ├── widget/                          (Glance DigestWidget)
│       │   │   ├── intents/                         (App Shortcuts provider)
│       │   │   └── services/                        (ShareReceiverActivity, EidosForegroundService, EidosNotificationListener)
│       │   ├── res/
│       │   │   ├── xml/network_security_config.xml
│       │   │   ├── xml/shortcuts.xml
│       │   │   └── values/strings.xml
│       │   └── assets/embedding/                    (MediaPipe or ONNX model file)
│       ├── test/                                    (JVM unit tests)
│       └── androidTest/                             (instrumented tests)
└── docs/
    ├── android-notes.md                             (OEM quirks, Doze, FGS types — recreated in A0.5)
    ├── hackathon-submission.md                      (judge-facing narrative — recreated in A9)
    └── sessions/                                    (YYYY-MM-DD_<topic>.md per meaningful session)
```

---

## Phase plan

### A0 — Foundation + observability

- Gradle project (KTS), version catalog, min SDK 31, target 35, arm64-v8a only
- Compose + Material 3 + NavHost; empty screens for Home / Chat / Memory / KB / Settings
- Room + DataStore wired (empty entities compile)
- kotlinx.serialization, OkHttp, Coroutines, AndroidX Security
- **Observability from day one**: `EidosLogger` (JSONL + os.log), `MetricsRecorder`, `FailureCategory`, `EidosFeatureFlags`, `BenchmarkRunner` skeleton, `BenchmarkCorpus` skeleton
- `proguard-rules.pro` with keep rules for Room + kotlinx.serialization + OkHttp + (future) LiteRT-LM JNI
- **Baseline Profiles** rule registered
- **APK signing**: upload keystore generated day one, backed up out-of-band
- CI: GitHub Actions (`assembleDebug` + unit tests + lint) on free Linux runners; self-hosted runner on the gaming PC for emulator instrumented tests

**Milestone**: `./gradlew :app:assembleDebug` green. App boots to empty tab bar. Diagnostics screen shows logger output. Benchmark harness callable with a stub `generate()`.

### A0.5 — OEM survival kit + policy foundation

- Android 14 `foregroundServiceType` declarations (`FOREGROUND_SERVICE_DATA_SYNC`, others as needed)
- Doze / App Standby documented in `docs/android-notes.md`; digest trigger designed around `setExactAndAllowWhileIdle`
- Battery-exception deep-links: Samsung, Xiaomi/MIUI, OPPO/ColorOS, OnePlus/OxygenOS, Huawei
- "Restricted Settings" (Android 13+) onboarding for NotificationListener enablement
- 16-KB page-size audit of every prebuilt native lib (sqlite-vec, MediaPipe, LiteRT-LM). Rebuild any unaligned.
- Model storage location: `context.filesDir` (survives updates, not data-clear). Surface path in Settings.
- NetworkSecurityConfig XML + OkHttp `CertificatePinner` — cleartext disabled, HF hosts pinned for the download window, revoked after
- `OemSurvivalKit.kt` utility for vendor-specific quirks

**Milestone**: Onboarding survives Samsung's aggressive kill. OEM deep-links tested on at least 2 vendor skins. 16-KB alignment verified.

### A1 — Persistence + embeddings

- Room schema: `KnowledgeEntry`, `EmbeddingRecord`, `Conversation`, `ConversationMessage`, `MemoryEntry`
- MediaPipe TextEmbedder integration first (Google stack); ONNX Runtime + all-MiniLM-L6-v2 fallback if coverage weak
- sqlite-vec loaded in `RoomDatabase.Callback.onOpen`
- `TextChunker`, `VectorStore`, hybrid RRF search — pure-Kotlin, unit-tested
- Content-hash dedup
- `KnowledgeRepository` + background indexing on `Dispatchers.IO`

**Milestone**: Insert entry → embeds in background → hybrid search returns it. JVM unit tests pass.

### A2 — LiteRT-LM inference bring-up (multimodal)

- LiteRT-LM Kotlin artifact integrated; Gemma 4 E2B `.task` bundle downloaded via `ModelDownloader` (WorkManager + HF `resolve/main/` URL)
- `GemmaSession` wraps LiteRT-LM streaming as `Flow<GenerationEvent>`
- Multimodal entry: `generate(messages, images, audio, reasoning)` — all three modalities wired day one (hackathon judges care about multimodal)
- `EgressGuard` armed post-download; airplane-mode smoke test
- `PromptTemplates` with runtime-context block (date, time, timezone, locale)
- Chat screen: Compose, `StreamingText`, message list, input bar with **text + mic + camera + photo picker**
- **Benchmark sweep** on real device: `BenchmarkCorpus` → tok/s, TTFT, RSS, thermal

**Milestone**: Real device, airplane mode, user types / speaks / captures image → Gemma 4 streams a response. Benchmark numbers posted to diagnostics.

### A3 — Memory + RAG + tool loop

- Pure-logic modules: `MemoryManager`, `MemoryIndex`, `MemoryDecayEngine`, `MemoryCrystallizer`, `ContextBuilder`, `RAGPipeline`
- Tool-call loop: parse JSON tool call → dispatch via `SkillRegistry` → re-prompt Gemma → natural-language confirmation
- `mem0`-style ADD / UPDATE / DELETE / NONE reconciliation during crystallization
- Long-context packing behind feature flag (~60 KB chars budget)
- Android `SpeechRecognizer` wired as thermal-throttle fallback

**Milestone**: "What did I tell you last week?" works. Conversations persist. "Remind me to call Sarah at 6 pm" creates a real calendar reminder.

### A4a — Platform data sources

- `CalendarSource` (CalendarContract read/write)
- `ContactsSource` (ContactsContract — budget extra time; API surface is gnarlier than iOS Contacts)
- `HealthSource` (Health Connect, graceful-degrade on Android <14)
- `LocationSource`, `MotionSource`, `MusicSource`
- Runtime permissions + onboarding copy per source

**Milestone**: Diagnostics → Sources panel shows "available: X of Y" with per-source test buttons.

### A4b — Skills + home

- 8 skills ported: SearchKB, AddNote, RememberFact, Calendar, Contacts, Reminders (→ CalendarContract), Digest, AppAction
- `AppActionSkills` via Android Intents (WhatsApp / SMS / Email / Phone / Maps) — pre-fill with confirmation sheet; no auto-send in v1
- HomeScreen (digest card) + HomeViewModel

**Milestone**: "What's on my calendar this week?" returns events. "Text Sarah I'll be late" opens WhatsApp pre-filled with confirmation.

### A5 — Ingestion + share

- `ShareReceiverActivity` handles `ACTION_SEND` / `ACTION_SEND_MULTIPLE` for text / url / image / file MIME types
- `WhatsAppImporter` (multi-locale regex), `MailImporter` (mbox + MIME decode), `PlainTextImporter`

**Milestone**: Share URL from Chrome → Eidos ingests. Share WhatsApp .txt export → parsed + searchable.

### A6 — Proactive + notifications + widget

- `ProactiveDigestWorker` via WorkManager; `AlarmManager.setExactAndAllowWhileIdle` trigger for morning digest (plain periodic WM is insufficient against Doze)
- `NotificationScheduler` for digest + nudges
- `DigestWidget` (Glance)
- **User-toggled ForegroundService** with mandatory ongoing notification; off by default

**Milestone**: Digest notification fires at user-configured time. Widget updates daily. Foreground service survives 24 h on Samsung.

### A7 — Safety + zero-egress demonstration (hackathon story)

- `SafetyGate` ported verbatim logic — regex + hardcoded crisis responses (988 Suicide Lifeline, 911, Poison Control, Childhelp, NSPCC, findahelpline.com)
- Unit tests: 40+ crisis phrases + false-positive guards ("killing it at work", "dying to see the movie")
- Always-on in RELEASE; debug can toggle for testing
- Diagnostics → Network tab shows "outbound requests since install: 0 (excluding model download)"
- Stretch: `VpnService`-based audit mode that logs every outbound socket

**Milestone**: Crisis query → hardcoded refusal with real emergency resources. Diagnostics proves zero egress post-download.

### A8 — Android-exclusive unlock (v1: minimal)

**v1 ships**:
- **A8.1** — `EidosNotificationListener` (NotificationListenerService) reading notifications as memory signal source. Opt-in per app. PII-stripped before reaching memory. **This is the "Android beats iOS" demo.**
- **A8.2** — `ShareReceiverActivity` (already shipped in A5)
- **A8.3** — User-toggled ForegroundService (already shipped in A6)

**Deferred to post-hackathon**:
- `AccessibilityService` (screen reading + tap injection) — 3-month maintenance tax; per-app UI heuristics; hard Play Store review story
- Auto-send messages (downstream of AccessibilityService)
- `CallScreeningService`
- `MediaProjection`
- Wear OS / Android Auto surfaces

### A9 — Hackathon submission polish

- README with "for good" narrative: on-device privacy, multimodal personal AI, zero telemetry, accessibility angle
- Demo video (2–3 min): chat with image + audio input, memory recall, digest notification, crisis-gate refusal, airplane-mode demo
- Screenshots for submission
- Release APK signed, uploaded to GitHub Releases
- `docs/hackathon-submission.md` with judge-facing highlights

**Milestone**: Submission package ready. `gh release create vX.Y` produces a public APK.

---

## Privacy posture

- **Zero egress after onboarding**: NetworkSecurityConfig permits only Hugging Face hosts during model-download window; revoked afterwards. `CertificatePinner` on those hosts.
- **No Firebase, Crashlytics, Google Analytics, or any third-party SDK that phones home.** Ever.
- **Optional VpnService audit layer** (A7 stretch): local VpnService forces every socket through an in-process proxy for receipts + enforcement. Stronger than any cloud assistant.
- **Health Connect**: read-only, insights cached in memory tier, raw samples never persisted.
- **NotificationListener**: prominent ongoing notification when active, opt-in per-app, PII-stripped before reaching memory.
- **ForegroundService**: user-toggled, mandatory ongoing notification, Settings kill switch.
- **Encrypted storage**: `EncryptedSharedPreferences` + `EncryptedFile` (AndroidX Security) for memory tiers and credentials.
- **Cleartext traffic disabled** in manifest.

---

## Top risks + mitigations

| Risk | Mitigation |
|---|---|
| LiteRT-LM Kotlin Gemma 4 multimodal rougher than text-only | Ship text first in A2; add image + audio in a tight A2b slice; fallback hackathon story emphasizes tool-use + RAG + privacy if multimodal blocks |
| OEM aggressive kill (Samsung/Xiaomi) breaks ForegroundService + WorkManager | A0.5 OEM survival kit with battery-exception deep-links |
| 3.58 GB Gemma 4 model vs app-data-clear behavior | `filesDir` storage; Settings shows path + size; docs explain uninstall behavior |
| 16-KB page alignment breaks prebuilt native libs | A0.5 audit + rebuild pass before any library ships |
| Solo dev + hackathon deadline | v1 scope hard-locked (minimal unlock only); A9 polish phase explicit |
| Upload keystore loss = no more updates | Day-1 out-of-band backup (password manager + encrypted drive) |
| AccessibilityService scope creep | Hard-deferred to post-hackathon. Not even a stub in v1 manifest. |

---

## Verification

- **JVM unit tests** for pure logic: `SafetyGate`, `TextChunker`, `VectorStore`, hybrid RRF, `PromptTemplates`, `MemoryCrystallizer`, `SkillParser`
- **Instrumented tests** for Room DAOs, WorkManager workers, Intent routing, permission flows
- **Compose UI tests** for Chat, Onboarding, Diagnostics critical paths
- **A2 real-device milestone**: airplane-mode chat + benchmark sweep
- **Submission gate**: APK signed, airplane-mode demo works end-to-end, SafetyGate passes full corpus, Diagnostics proves zero egress

---

## End-of-session ritual

Before concluding any meaningful session:

1. Update the **Current State** table above if a phase's status changed
2. Write a session record under `docs/sessions/YYYY-MM-DD_<topic>.md` — decisions, open items, what's next
3. Commit with an imperative-mood message; one concern per commit

---

## Files Claude/Codex should read when picking up a session

1. `plan.md` (this file) — current state, phase plan, design decisions
2. `CLAUDE.md` — working rules
3. `docs/sessions/` — newest first, full session records
4. `docs/android-notes.md` — OEM quirks and Android-specific gotchas
5. Recent `git log --oneline -20`
