# Session log — 2026-04-25 — Phase A0 foundation

## Goal

Land the Android scaffolding + observability foundation so every subsequent
phase has (a) a compilable Gradle project, (b) a working Diagnostics screen
to measure itself against, and (c) a benchmark harness callable before
LiteRT-LM arrives in A2.

## What shipped

### Build tooling

- `settings.gradle.kts` — plugin + dependency repo resolution
- `build.gradle.kts` (root) — apply-false plugin declarations
- `gradle.properties` — parallel + caching + configuration-cache enabled,
  AndroidX flags, Kotlin incremental
- `gradle/libs.versions.toml` — full version catalog: AGP 8.7.3, Kotlin
  2.1.0, Compose BOM 2024.12.01, Room 2.6.1, DataStore 1.1.1, Coroutines
  1.9.0, OkHttp 4.12.0, kotlinx.serialization 1.7.3

### App module

- `app/build.gradle.kts` — namespace `com.hissamuddin.eidos`, min SDK 31,
  target 35, arm64-v8a only, Kotlin source root `src/main/kotlin`,
  Compose + BuildConfig enabled
- `app/proguard-rules.pro` — keep rules for Kotlin metadata, coroutines,
  kotlinx.serialization, Room, OkHttp, Compose; placeholder sections for
  LiteRT-LM / MediaPipe (filled in A2)

### Manifest + resources

- `AndroidManifest.xml` — Internet + POST_NOTIFICATIONS only; no cleartext;
  network security config + data extraction rules wired
- `res/xml/network_security_config.xml` — cleartext denied; HuggingFace
  hosts allowed (pinned during model download only)
- `res/xml/backup_rules.xml` + `data_extraction_rules.xml` — exclude every
  domain; no Google cloud backup of personal data
- Adaptive launcher icon via XML vectors (no binaries)
- `values/strings.xml` — nav labels, placeholder copy per empty screen,
  diagnostics labels

### Observability core

- `platform/diagnostics/FailureCategory.kt` — enum taxonomy mirroring the
  iOS schema so JSONL stays stable
- `platform/diagnostics/EidosLogger.kt` — JSONL + logcat mirror; crash-safe
  write loop; `logStream` SharedFlow for Diagnostics' live tail; never
  throws from the caller's thread
- `platform/diagnostics/MetricsRecorder.kt` — per-generation probe with
  TTFT / tok/s / RSS (via `Debug.MemoryInfo`) / thermal; recent-100 ring
  exposed as StateFlow for the UI
- `platform/diagnostics/EidosFeatureFlags.kt` — DataStore-backed flags with
  Kotlin Flow observation; `setSafetyGateEnabled` is a no-op in RELEASE

### Benchmark harness + stub inference

- `inference/GemmaSession.kt` — sealed interface for the Gemma session;
  includes `StubGemmaSession` that emits a canned ~10-token reply at
  ~20 tok/s so the benchmark harness exercises `MetricsRecorder` before
  LiteRT-LM lands
- `platform/diagnostics/BenchmarkCorpus.kt` — 11-category skeleton. Short
  chat, reasoning, refusal, and hallucination have real prompts + rubrics.
  Tool use, RAG, vision, and audio are placeholders for their owning phases.
- `platform/diagnostics/BenchmarkRunner.kt` — sequential runner, per-prompt
  metric probe, pass/fail against rubric, `BenchmarkReport` output

### Room skeleton

- `knowledgebase/KnowledgeEntry.kt`, `EmbeddingRecord.kt`, `Conversation.kt`,
  `ConversationMessage.kt`, `MemoryEntry.kt` — `@Entity` declarations with
  indices matching the iOS schema. DAOs intentionally absent — filled in A1.
- `KnowledgeDatabase.kt` — `@Database` with process-wide singleton +
  `fallbackToDestructiveMigrationOnDowngrade()`. `onOpen` callback reserved
  for sqlite-vec load in A1.

### UI

- `App.kt` — `Application` with a lazy `AppContainer` holding the
  dependency graph (manual DI, no Hilt)
- `ui/MainActivity.kt` — single-Activity, edge-to-edge, Compose host
- `ui/LocalAppContainer.kt` — CompositionLocal
- `ui/theme/` — Material 3 with dynamic color on Android 12+, brand
  palette fallback, monospace `labelMedium`
- `ui/Destination.kt` — 5 top-level routes + Diagnostics sub-route
- `ui/EidosApp.kt` — Scaffold + NavigationBar + NavHost
- `ui/home/`, `ui/chat/`, `ui/memory/`, `ui/kb/` — placeholder screens
- `ui/settings/SettingsScreen.kt` — list with Diagnostics entry
- `ui/settings/DiagnosticsScreen.kt` — 4 tabs (Logs / Metrics /
  Benchmarks / Flags). Logs tail collects `logStream`; Benchmarks runs
  `BenchmarkRunner.runAll()` via the button; Flags toggles every entry
  in `EidosFeatureFlags`

### Tests

- `FailureCategoryTest.kt` — schema stability (wire names)
- `EidosLoggerTest.kt` — 4 tests: JSONL schema, failure field, live stream,
  never-crash-on-IO-error
- `BenchmarkCorpusTest.kt` — id uniqueness, non-empty text, shipped-category
  coverage, rubric case-insensitivity

### CI

- `.github/workflows/android-ci.yml` — `assembleDebug`, unit tests, lint on
  free Ubuntu runner; uploads APK + reports as artifacts. Triggers on push
  and PR against `eidos-android`.

## Decisions made this session

1. **Manual DI over Hilt.** Hilt's KSP overhead on solo-dev Gradle cycles
   isn't worth it at A0 scale. `AppContainer` + CompositionLocal is
   fine through A8.
2. **arm64-v8a only.** Flagship-class Android floor (hackathon judges will
   not test on armv7). Keeps APK size small and simplifies native-lib
   16 KB alignment work in A0.5.
3. **Dynamic color on.** Android 12+ is our min anyway; feels native.
4. **No launcher icon binaries.** Adaptive XML vector avoids committing
   bitmap assets at this stage.
5. **Logger schema stable day one.** JSONL fields are `ts / level /
   category / msg / data / failure` — documented in KDoc, tested against
   a fixed clock.
6. **Benchmark placeholders shipped alongside real prompts.** Lets the
   runner smoke-test against any category without waiting for A2b vision
   assets.
7. **Logger dispatcher is scope-controlled, not hardcoded.** Fixed a bug
   where `scope.launch(Dispatchers.IO)` made tests non-deterministic.
   Production still uses `Dispatchers.IO` via the `create()` factory.

## Open items — resolve before leaving A0

- [ ] User runs `./gradlew :app:assembleDebug` on the RDC and confirms
      a green build. This local machine has no Gradle / Android SDK, so
      build verification is deferred to the RDC.
- [ ] Gradle Wrapper. I did not write `gradlew` / `gradle-wrapper.jar`
      (the latter is a binary and `gradle wrapper` must be invoked with a
      local Gradle install). On the RDC, run `gradle wrapper
      --gradle-version 8.11` once, then commit `gradle/wrapper/` +
      `gradlew` + `gradlew.bat`.
- [ ] Android Studio's first open will download Metal Toolchain /
      Android SDK — no action needed beyond accepting the license
      prompts.

## Milestone status

Per `plan.md` A0 milestone:

> `./gradlew :app:assembleDebug` green. App boots to empty tab bar.
> Diagnostics screen shows logger output. Benchmark harness callable
> with a stub `generate()`.

**Proved on this machine**: code shape + engineering-bar compliance.
**Blocked on RDC verification**: actual `assembleDebug` green + APK boot.

## Next session

A0.5 — OEM survival kit. Before any proactive UI (A6), we owe the app:
- Foreground service type declarations
- Battery-exception deep-links per OEM
- Restricted-settings onboarding for NotificationListener (A8.1)
- 16 KB page-size audit of sqlite-vec / ORT / LiteRT-LM prebuilts
- Model storage location decision (`filesDir`, surfaced in Settings)

Once A0.5 lands, A1 (persistence + embeddings) is unblocked.
