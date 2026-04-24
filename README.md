# Eidos — Android

An on-device personal AI assistant. Gemma 4 runs locally via Google AI Edge
(LiteRT-LM). **Zero data egress** after the one-time model download. Built
for the **Google Gemma 4 for Good Hackathon**.

> **Current phase**: A0 (foundation shipped). See [plan.md](plan.md)
> for the full phase map and what's shipped vs. pending.

---

## Requirements

| Tool | Version |
|---|---|
| JDK | **17** (Temurin / Adoptium recommended) |
| Android Studio | **Ladybug (2024.2.1)** or newer |
| Android SDK | Platform **35** (Android 15), Build-Tools **35.0.0+** |
| Gradle | **8.11** (via wrapper; generated on first run) |
| Kotlin | 2.1.0 (bundled with the catalog — do not install separately) |
| Device for inference | Pixel 7+ / Galaxy S22+ / SD 8 Gen 2+ / Tensor G2+, 8 GB RAM, arm64-v8a |
| Free disk | ~10 GB (Android SDK + build caches + Gemma 4 E2B ≈ 3.58 GB at runtime) |

The emulator is fine for UI / tests / DAO work. Inference benchmarks from
phase **A2** onwards require a real device — LiteRT-LM + GPU/NPU delegates
are not meaningful on an x86\_64 emulator.

---

## First-time setup

### 1. Clone + checkout the Android branch

```bash
git clone https://github.com/Hammad-Anjum/Eidos.git
cd Eidos
git checkout eidos-android
```

All Android work lives on `eidos-android`. `main` is a separate iOS track.

### 2. Generate the Gradle wrapper (once per workspace)

The repo intentionally does not commit `gradle-wrapper.jar` yet. On your
dev box, run this once:

```bash
gradle wrapper --gradle-version 8.11
```

That produces `gradlew`, `gradlew.bat`, and `gradle/wrapper/`. If you don't
have a system `gradle` installed, opening the project in Android Studio
will offer to download the wrapper for you — accept.

After it's generated, commit it:

```bash
git add gradlew gradlew.bat gradle/wrapper
git commit -m "Add Gradle wrapper 8.11"
git push
```

### 3. Open in Android Studio

`File → Open → <repo root>`. On first sync:

- Android Studio downloads **SDK platform 35** + **Build-Tools 35**.
- Accept the SDK licenses prompt.
- Gradle sync resolves the version catalog and pulls every dependency.

Sync can take 5–15 minutes on the first run (AndroidX + Compose + Room +
AGP components). Subsequent syncs hit the cache and finish in seconds.

### 4. (Optional) Generate the signing keystore

Release builds need a keystore. Generate it on day one and back it up out
of band — lose it and you cannot ship app updates again.

```bash
keytool -genkey -v \
  -keystore keystore/upload.keystore \
  -alias eidos-upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

The `.keystore` file is already in `.gitignore`. Store the password in
your password manager.

> Release signing isn't wired in `app/build.gradle.kts` yet. The release
> buildType currently fails loudly until the signing config lands in A9.

---

## Building

| Task | Command |
|---|---|
| Debug APK | `./gradlew :app:assembleDebug` |
| Install on connected device/emulator | `./gradlew :app:installDebug` |
| Clean | `./gradlew clean` |
| Show dependency tree | `./gradlew :app:dependencies` |

The APK lands at `app/build/outputs/apk/debug/app-debug.apk`.

---

## Running

### On an emulator

Any AVD with **API 31+** works for UI + Room + DataStore + WorkManager +
Compose. Inference calls through `StubGemmaSession` — you'll see a canned
response in A0 and real Gemma 4 output from A2 onwards (A2 requires a real
device regardless).

### On a real device

1. Enable **Developer Options** (tap Build Number 7×).
2. Enable **USB Debugging**.
3. Connect via USB (or ADB-over-WiFi: `adb tcpip 5555`, then `adb connect <phone-ip>:5555`).
4. `./gradlew :app:installDebug`.
5. Launch **Eidos** from the app drawer.

---

## Verifying the A0 milestone

After `installDebug` succeeds, walk through these to confirm the
foundation is intact:

1. **Boot**. App launches to a bottom-nav with **Home / Chat / Memory /
   Knowledge / Settings**.
2. **Diagnostics**. Settings → **Diagnostics**. You'll see four tabs:
   **Logs / Metrics / Benchmarks / Flags**.
3. **Logs tab**. Open it and navigate around the app — every lifecycle
   event ("Application onCreate") appears as a log entry with a
   millisecond-precision UTC timestamp.
4. **Benchmarks tab**. Tap **Run benchmarks**. A progress bar advances
   through ~11 prompts; the report populates with pass/fail per prompt.
   The `StubGemmaSession` produces a canned reply, so safety-gate probes
   like "I want to hurt myself" will fail the keyword rubric until the
   real `SafetyGate` lands in A7 — this is expected behavior right now.
5. **Metrics tab**. After the benchmark run, metrics appear: TTFT,
   tok/s, RSS before/peak/after, thermal state.
6. **Flags tab**. Toggle any flag. Confirm it round-trips through
   DataStore — kill the app, relaunch, toggle survives.
7. **On-disk log**. Logs persist to
   `filesDir/eidos/logs/YYYY-MM-DD.jsonl`. To inspect:

   ```bash
   adb shell run-as com.hissamuddin.eidos cat files/eidos/logs/$(date -u +%Y-%m-%d).jsonl
   ```

   Each line is a standalone JSON record with fields `ts`, `level`,
   `category`, `msg`, `data`, `failure`.

---

## Testing

| Task | Command |
|---|---|
| JVM unit tests | `./gradlew :app:testDebugUnitTest` |
| Instrumented tests (needs device/emulator) | `./gradlew :app:connectedDebugAndroidTest` |
| Android Lint (debug) | `./gradlew :app:lintDebug` |
| All checks | `./gradlew check` |

A0 ships three JVM test classes:

- `FailureCategoryTest` — wire-name stability
- `EidosLoggerTest` — JSONL schema, live stream, crash-safe write
- `BenchmarkCorpusTest` — id uniqueness, rubric behavior

**Expected**: all 3 classes green. Coverage targets (70% overall, 95% on
SafetyGate / skills / memory crystallization) apply from A3 onwards when
those modules ship.

---

## Continuous Integration

`.github/workflows/android-ci.yml` runs on every push + PR against
`eidos-android`:

1. `assembleDebug`
2. `testDebugUnitTest`
3. `lintDebug`
4. Uploads the APK + lint report + test report as workflow artifacts

The workflow runs on free Ubuntu runners (Linux JDK 17, SDK installed on
the fly). Instrumented tests are not in CI — run those locally on the
emulator or self-host a runner on the gaming PC when that becomes worth it.

---

## Project structure

```
/                                 Gradle root
├── plan.md                       Source of truth — phase plan + current state
├── CLAUDE.md                     Working rules for Claude sessions on this repo
├── README.md                     This file
├── settings.gradle.kts           Module graph
├── build.gradle.kts              Plugin declarations (apply-false)
├── gradle.properties             JVM args, Kotlin/KSP flags
├── gradle/libs.versions.toml     Version catalog
├── app/                          The one Android module
│   ├── build.gradle.kts          App module config
│   ├── proguard-rules.pro        R8 keep rules
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   ├── kotlin/com/hissamuddin/eidos/
│       │   │   ├── App.kt                        Application + AppContainer
│       │   │   ├── inference/                    GemmaSession (stub in A0)
│       │   │   ├── knowledgebase/                Room entities + DB
│       │   │   ├── platform/diagnostics/         Logger, Metrics, Flags, Bench
│       │   │   └── ui/                           Compose screens + theme
│       │   └── res/                              Strings, themes, XML configs
│       ├── test/kotlin/...                       JVM unit tests
│       └── androidTest/kotlin/...                Instrumented tests (A1+)
├── docs/
│   └── sessions/                                 Per-session decision logs
└── .github/workflows/android-ci.yml              CI
```

See [plan.md](plan.md) for the full module-per-phase map.

---

## Troubleshooting

### "Task 'wrapper' not found"

You need a system `gradle` installed to bootstrap the wrapper. Either:

- Install Gradle 8.11 via [SDKMAN](https://sdkman.io/): `sdk install gradle 8.11`
- Or open the project in Android Studio, which bundles Gradle and will
  generate the wrapper on sync.

### "SDK location not found"

Android Studio writes `local.properties` with `sdk.dir=...` on first open.
If you're building purely via CLI, create it manually:

```
sdk.dir=C\:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
```

(or the equivalent path on your machine). Never commit `local.properties`.

### "Kotlin version / KSP version mismatch"

The Kotlin version in `gradle/libs.versions.toml` must match KSP's prefix
(e.g. Kotlin `2.1.0` ↔ KSP `2.1.0-1.0.29`). Bumping one without the other
fails Gradle sync. Both live in the catalog — change them together.

### "Metadata has an inconsistent compile-time Kotlin version"

A dependency was built against a newer Kotlin than ours. Either bump
Kotlin in the catalog (carefully, retest) or pin the dependency to an
older release.

### The app installs but crashes on launch

Check logcat with `adb logcat Eidos/*:V *:E`. Every `EidosLogger` category
tags as `Eidos/<category>`. Common culprit during setup: missing
`POST_NOTIFICATIONS` runtime permission (the first `notification` call
after A6 lands).

### Release build fails with "no signingConfig"

Expected for now. The release buildType in `app/build.gradle.kts`
intentionally fails until the signing config lands in A9 (hackathon
submission polish). Debug builds work fine.

### OEM (Samsung/Xiaomi/OPPO) silently kills background work

Expected pre-A0.5. Those devices require per-OEM battery-exception
deep-links during onboarding — that's scoped for **A0.5**. Until then,
WorkManager jobs and the foreground service may be killed after 10–30
minutes on aggressive skins.

### `adb` shell `run-as` fails on release builds

`run-as` requires a debuggable build. Use `./gradlew :app:installDebug`,
not `installRelease`, for log inspection.

---

## Contributing workflow (solo for now)

1. Work on a feature branch off `eidos-android`:
   `git checkout -b feature/a0.5-oem-kit`
2. Commit in imperative mood, one concern per commit.
3. Push; CI runs `assembleDebug + tests + lint`.
4. Merge back to `eidos-android` once CI is green.
5. Update [plan.md](plan.md) Current State table if a phase advances.
6. Write a session log under `docs/sessions/YYYY-MM-DD_<topic>.md` for
   meaningful sessions.

---

## Where to read next

- [plan.md](plan.md) — phase-by-phase build plan, locked decisions
- [CLAUDE.md](CLAUDE.md) — working rules for Claude Code / Codex sessions
- [docs/sessions/](docs/sessions/) — chronological decision logs
- [.github/workflows/android-ci.yml](.github/workflows/android-ci.yml) — CI pipeline
