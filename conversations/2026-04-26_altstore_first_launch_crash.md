# 2026-04-26 — AltStore First-Launch Crash Triage

## Context

A first external tester installed Eidos through AltStore and reported that the app crashed
without an in-app explanation.

## Findings

- The previously shared tester IPA was a debug-style build that embedded widget/share
  extensions and debug artifacts.
- The app bundle requires iOS 26.0 or newer.
- The Release iPhone build succeeds.
- The Release app bundle still embeds `EidosWidget.appex` and `EidosShareExtension.appex`
  by default, which can add AltStore/free-team signing risk.
- The tester reached "Loading model into memory..." and then crashed.
- Follow-up confirmed the tester selected the larger E4B model. That is the likely
  first-load crash path and should not be exposed to nontechnical Release testers yet.

## Action Taken

- Built a Release iPhone app bundle with:
  - `xcodebuild -scheme Eidos -destination generic/platform=iOS build -configuration Release`
- Packaged a main-app-only AltStore IPA that excludes:
  - `PlugIns/`
  - `*.debug.dylib`
  - `__preview.dylib`
- Created:
  - `build/Eidos-AltStore-Release-MainOnly.ipa`
  - `build/Eidos-Tester-Pack-Release-MainOnly.zip`
- Changed first-run model selection:
  - E2B is now always the default model.
  - Release builds expose E2B only.
  - E4B remains DEBUG/dev-only until E2B passes real-device loading.
  - Stale stored E4B selections sanitize back to E2B in Release.
- Added regression tests for the E2B default/selectable path.
- Ran simulator tests after the guardrail change: 189 / 189 passing.
- Attempted to rebuild the fixed Release IPA, but the sandboxed Xcode process
  could not write SwiftPM / clang manifest caches under the real user home and
  unrestricted approval was rejected. A temporary tester zip was created around
  the previous main-app-only IPA with explicit "choose E2B only" instructions:
  `build/Eidos-Tester-Pack-Release-MainOnly-Choose-E2B.zip`.
- Follow-up tester report: app opened directly to Home, first chat produced a
  blank response, then crashed. That means startup trusted persisted model state
  before proving MLX had a loaded model.
- Hardened startup readiness:
  - `ModelDownloader.isModelDownloaded` now verifies required model files exist
    and are non-empty before trusting the persisted flag.
  - `AppContainer.bootstrap()` marks `.loading` while warming a cached model,
    marks `.ready` only after `gemma.load(...)` succeeds, and clears stale state
    on load failure.
  - `EidosApp` now gates `RootView` on `phase == .ready` only.
  - `StartupModelStatusView` shows visible download/loading/failure states
    instead of a generic startup spinner.
- Added 3 regression tests for missing, empty, and complete model directories.
- Ran simulator tests after startup readiness hardening: 192 / 192 passing.
- Ran signed generic iOS build: `xcodebuild -scheme Eidos -destination generic/platform=iOS build -skipMacroValidation` succeeded.
- Sandbox could not build a fresh Release IPA because SwiftPM manifest diagnostics
  still targeted `/Users/sditeam/Library/Caches/...`; escalation was rejected by
  the environment. Packaged the already-built Debug device app instead for an
  immediate smoke test:
  `build/Eidos-Tester-Pack-StartupFix-Debug-Clean.zip`.

## Tester Instructions

The tester should delete the old Eidos install, install the new main-app-only IPA, confirm
the iPhone is on iOS 26.0 or newer, and capture the newest `Eidos` crash report from:

Settings → Privacy & Security → Analytics & Improvements → Analytics Data

## Open Items

- Exact crash reason is unknown until the tester sends the `.ips` crash report.
- If the E2B-only Release build still crashes, inspect the crash log before making
  further model/runtime changes.
- Best next tester artifact is still a clean Release main-app-only IPA rebuilt
  outside the sandbox. The Debug startup-fix pack is acceptable for a quick
  functional smoke test only.

## Follow-up: no download bar after force-download build

Tester again reported direct Home with no visible download bar. Diagnosis:
`OnboardingView` already passed `forceDownload: true`, but that path was too
late if `AppContainer.bootstrap()` trusted cached model state first and marked
the app ready before onboarding rendered.

Action taken:

- Added a Release-device-only one-time external tester marker:
  `2026-04-26-force-model-redownload-v2`.
- `AppContainer.bootstrap()` calls the tester reset before checking
  `modelDownloader.isModelDownloaded`, so stale state cannot bypass onboarding.
- `ModelDownloader.clearDownloadedModelState(...)` can now delete local model
  files, not just clear the UserDefaults flag.
- `ModelDownloadView(forceDownload: true)` deletes the selected variant folder
  before starting the download, preventing HuggingFace/local-file skip behavior
  from hiding the progress bar.
- Ran simulator tests: 193 / 193 passing.
- Ran Release generic iOS build successfully with:
  `xcodebuild -scheme Eidos -destination generic/platform=iOS build -configuration Release -skipMacroValidation`.
- Packaged verified main-app-only tester artifact:
  `build/Eidos-Tester-Pack-ForceFreshDownload-Release-MainOnly-v2.zip`.

Verification:

- IPA contains no `PlugIns/`.
- IPA contains no matched `*.debug.dylib` or `__preview.dylib`.
- IPA includes `mlx-swift_Cmlx.bundle/default.metallib`.
- Compiled binary contains the force-fresh marker and log event names.

Next tester run should use only the `ForceFreshDownload` v2 zip. If it still
goes straight to Home, the installed IPA is stale or AltStore reinstalled an
older cached build.
