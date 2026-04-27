# Phase 8 Completion — 2026-04-25

## Goal

Close Phase 8 in an honest way:
- finish the repo-owned multimodal + observability work
- restore a green test/build baseline
- document the one remaining upstream boundary instead of leaving it as a fuzzy TODO

## What changed

### Safety / correctness

- Expanded `SafetyGate` self-harm coverage to catch `"I wish I was dead"`.
- Updated stale prompt/parser tests to match the current prompt-injection and JSON-recovery contract.

### Multimodal path

- `ChatInputBar`, `ChatView`, and `ChatViewModel` now carry image attachments end-to-end and are future-ready for audio attachments.
- `GemmaSession.generate(messages:images:audio:reasoning:)` now explicitly documents and enforces the current boundary:
  - image input runs through the `MLXVLM` path
  - raw audio is **not** natively consumable yet because the current `mlx-swift-lm` public API exposes images/videos but not audio attachments
- `BenchmarkRunner` now feeds concrete synthetic image fixtures into vision prompts, with stable OCR/scene rubrics.

### Tests / verification

- Added:
  - `BenchmarkRunnerTests`
  - `AudioCaptureServiceTests`
  - `GemmaSessionMultimodalTests`
- Restored full simulator suite to green:
  - `174 / 174` tests passing on iPhone 17 simulator
- Verified unsigned device compile:
  - `xcodebuild -scheme Eidos -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -skipMacroValidation`
  - result: `BUILD SUCCEEDED`

### Warning cleanup

- `LocationSource` migrated from deprecated `CLGeocoder` calls to `MKReverseGeocodingRequest`.
- `project.yml` now declares full iPad orientations so the Info.plist warning about requiring full-screen no longer blocks the "zero-warning" bar.

## Product / planning outcome

- `masterplan.md` now marks **Phase 8 complete**.
- The remaining raw-audio item is reclassified from "unfinished internal work" to **upstream dependency**:
  - `GemmaSession.supportsNativeAudioInput = false`
  - default shipping voice path remains fully-local `SpeechTranscriber`
  - `AudioCaptureService` and `audio: Data?` plumbing stay in place for the first upstream MLX release that exposes raw audio attachments

## Next step

- Start **Phase 9 — Skills / Personas**
- Keep the native raw-audio bridge on the backlog only as an upstream-watch item, not as something that blocks Phase 9 work
