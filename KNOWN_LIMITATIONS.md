# Known Limitations & Deferred Work

This is the honest inventory. If you're thinking "wait, does it really do X?" — check here before assuming yes.

**Last updated: 2026-04-26, after AltStore model-load/startup triage.** For the full phase status see `masterplan.md`.

## ✅ Items previously listed as missing that have since shipped

Removed from the deferred list because they now exist and work:
- **Share Extension** — `EidosShareExtension` target + `ShareViewController` wired to App Group queue (functional on paid Apple Developer accounts; free-tier requires sideloading with entitlement caveats)
- **App Intents / Shortcuts / Spotlight** — 23 intents, 10 Siri phrases, full Shortcuts catalogue
- **Widget / Live Activity / Control Widgets (iOS 18+)** — all shipped in `EidosWidget` target
- **Diagnostics / metrics** — `DiagnosticsView` exposes live logs, per-generation metrics, benchmarks, feature flags, chat-history browser
- **Conversation browser** — Settings → Diagnostics → Chats, markdown export per thread
- **Ambient data pipeline** — `AmbientSnapshotAssembler` aggregates location + motion + music + calendar + health, injects into every chat turn as `# Right now`
- **Skill pipeline** — `SkillParser` + `SkillRegistry` + tool-call loop fully wired in `RAGPipeline` (Brain Fix 2026-04-23)
- **Prompt-injection defence** — retrieved context fenced in `<untrusted>` tags; Gemma explicitly instructed not to execute instructions from them
- **mem0-style memory reconciliation** — ADD/UPDATE/DELETE/NONE instead of blind insert
- **SafetyGate** — pre-LLM crisis refusal with hardcoded resources
- **Thermal-aware budgets** — `DeviceProfile` scales context + tokens + tool-hop cap by form factor and thermal state
- **Multimodal chat + benchmark path** — camera + photo picker wired through chat, `MLXVLM` image path wired, synthetic benchmark fixtures shipped
- **Model switcher** — Settings → Switch model exists; Release tester builds expose E2B only until real-device E2B loading is validated

## Real gaps (should be fixed before shipping)

### Inference hasn't been validated end-to-end in the real app
The standalone `mlx-probe` Swift package loads Gemma 4 E2B from a local directory and produces output — that proves MLX + the model format + the model config we pass are correct. But **no one has yet clicked through the deployed Eidos app and watched Gemma stream a response into the chat bubble**. The two times we tried:
- iOS Simulator — MLX crashes in C++ because simulator Metal can't run custom shaders.
- Mac (Designed for iPad) — sandbox blocks the pre-downloaded `/Users/.../eidos-models/` path we used to side-load. We fixed this by copying the model into the app's sandbox container.

Next step: a real iPhone 15 Pro+ running iOS 26 (current `deploymentTarget` in `project.yml`). Full checklist in `masterplan.md` Phase 2d. Note: older iPhones (13/14, or 15 non-Pro) are below the floor — Gemma 4 E2B needs Apple Silicon A17+ class to run comfortably under thermal constraints.

### E4B is disabled in Release tester builds
The first external AltStore tester selected the larger E4B model and the app
crashed while MLX was loading it into memory. Until E2B has passed real-device
loading and first chat on multiple iPhones, Release tester builds force E2B as
the default and only selectable onboarding model. E4B stays as a DEBUG/dev path.

### Startup readiness now verifies model files
After the first tester pass, we found a stale `eidos.modelDownloaded` flag could
send the app to Home even when the local model directory was missing or incomplete.
The startup gate now requires `ModelDownloader.phase == .ready`, verifies all
required HuggingFace files are present and non-empty, and shows a visible
loading/download state until MLX actually loads the model.

### External tester builds force a fresh model download once
The second tester pass still opened directly to Home, which meant onboarding
was being bypassed before its `forceDownload` path could run. Release tester
builds now carry a one-time force-fresh marker that clears the stale download
flag and deletes old `gemma-e2b` / `gemma-e4b` folders before cached-model
bootstrap can run. This is an AltStore validation guardrail, not a permanent
production update policy.

### No real Share Extension (RESOLVED, see above)
Now shipped. Left the stanza removed.

### No App Intents / Shortcuts / Spotlight integration (RESOLVED, see above)
Now shipped. Left the stanza removed.

### No routine learning
Phase 6.1. Detecting patterns over calendar/location/health requires months of accumulated data. The *infrastructure* to ingest those signals is in place (CalendarSource, HealthSource, MemoryManager) — the actual pattern-detection pass is deferred until there's real usage data to learn from.

### No life-logging / ambient day-shape
Phase 6.4. Nightly crystallization across calendar + health + locations needs a BackgroundTasks registration and a longer Gemma call chain. Deferred.

### No tone engine
Phase 6.5. Learning how the user writes to different contacts requires a corpus of their messages — which requires Share Extension ingestion of WhatsApp/Mail. Unlocked by 5.2.

### No relationship intelligence
Phase 4.3. Contact-level communication signals (how often, last interaction, important dates) would need message ingestion first. Deferred with 5.2/6.5.

### No Widget / Live Activity (RESOLVED, see above)
Shipped in `EidosWidget` target.

## Soft limitations (known but acceptable for now)

### EgressGuard is advisory for the HuggingFace download path
`URLProtocol.registerClass` only applies to sessions using the default configuration. The `swift-huggingface` client creates its own URLSession and bypasses the guard. We observed this empirically during Phase 2 debugging. Our own `HuggingFaceDownloader` (which we ship with) DOES use `URLSession.shared`, so the guard applies there. For production privacy-hardening we'd need to either:
- Swap out `swift-huggingface` for our own downloader entirely (partially done; the macro-based loader still uses it)
- Or pin HTTPS certificates on every client and audit transitively

### Native raw audio into Gemma is upstream-blocked
Gemma 4's config includes audio support, and the `MLXVLM` model internals in `mlx-swift-lm` know about audio tokens. But the current public `UserInput` / `Chat.Message` API surface exposed by the package still only accepts images and videos, not raw PCM attachments. Eidos therefore ships fully-local voice input through `SpeechTranscriber` by default, while `AudioCaptureService` and the `GemmaSession.generate(...audio:)` plumbing stay ready for the first upstream release that exposes the attachment API.

### Conversation history browser (RESOLVED, see above)
Settings → Diagnostics → Chats now lists every `Conversation` with per-thread markdown export.

### No metrics / observability (RESOLVED, see above)
`EidosLogger` + `MetricsRecorder` + Settings → Diagnostics gives live logs, per-generation metrics, benchmarks, flags.

### Accessibility coverage is partial
Most interactive elements have system-provided accessibility, but not everything has explicit labels. No VoiceOver-tested flow. No Dynamic Type review. Quick wins available in a focused pass.

### Permission strings are one-sentence
Friendly-enough but not bulletproof. Apple's reviewers are strict; we'd want to sharpen these before App Store submission.

### Phone-number parsing is naive
`AppAction.cleanPhone` just strips non-digits except `+`. No E.164 validation, no internationalization helper. Good enough for the common case.

### No first-run data model migration plan
If we ship v1 with the current Schema and later add fields, SwiftData's `VersionedSchema` needs to be wired up. Not built.

## Environmental gotchas

### First-launch model download takes time
On WiFi, ~3–10 minutes for E2B (1.5 GB). The UI shows progress. If the XET/CAS service at HuggingFace fails (we observed this during Phase 2 build-out), the download stalls. Our `HuggingFaceDownloader` uses the legacy `resolve/main/` path, which avoids the xet backend — but if HF changes their CDN we'd have to update.

### Xcode macro trust is manual
The `MLXHuggingFaceMacros` package uses Swift macros that Xcode requires the user to manually trust via the "Enable Macros" dialog. On CI this is bypassed with `-skipMacroValidation`. First-time builders will hit this prompt.

### Metal Toolchain is a separate Xcode component
`xcodebuild -downloadComponent MetalToolchain` (687 MB) is required before the MLX Metal shaders can compile. A fresh Xcode install won't have it.

### Simulator is permanently broken for inference
MLX's custom Metal shaders return null on the iOS Simulator. This is not fixable from our side — Apple's simulator Metal doesn't implement what MLX needs. Use "My Mac (Designed for iPad)" or a real device.

## What we've tested

- 193 unit/integration tests, all passing on iPhone 17 simulator
- Unsigned `generic/platform=iOS` build succeeds with `-skipMacroValidation`
- Signed `generic/platform=iOS` build succeeds after startup readiness hardening
- Standalone `mlx-probe` confirms Gemma 4 E2B loads and generates text on macOS
- Simulator multimodal smoke covers image input and future-ready audio parameter plumbing without crashing the chat/model path

## What we haven't tested

- A real iPhone running the deployed app
- Airplane-mode inference (the EgressGuard validation)
- Memory behavior over weeks/months of usage
- Thermal behavior under sustained generation
- Notification scheduling across reboots / background app refresh interactions
- HealthKit queries against real data (we have the code; no live data in our test env)
- Share-extension ingestion on a physical device with a paid Apple Developer App Group provision (code is wired, entitlement registration needs paid team)

## Tests at time of writing

193 tests across:
- `SkillParserTests`, `TextChunkerTests`, `VectorStoreTests`, `RRFusionTests` (Phase 1)
- `EgressGuardTests`, `PromptTemplatesTests` (Phase 2)
- `MemoryManagerTests`, `MemoryIndexTests`, `MemoryDecayEngineTests`, `MemoryCrystallizerTests`, `ContextBuilderTests`, `RAGIntegrationTests` (Phase 3)
- `SkillsTests` (Phase 4)
- `AppActionTests`, `ImporterTests` (Phase 5)
- `HealthInsightTests`, `NotificationSchedulerTests` (Phase 6)
- `PromptInjectionFenceTests`, `PromptTemplatesRuntimeTests`, `RAGPipelineToolLoopTests`, `SkillPipelineIntegrationTests`, `SafetyGateTests`, `RememberFactSkillTests`, `EidosLoggerTests`, `BenchmarkRunnerTests`, `AudioCaptureServiceTests`, `GemmaSessionMultimodalTests`, `MarkdownBlockParserTests` (Phase 8)
