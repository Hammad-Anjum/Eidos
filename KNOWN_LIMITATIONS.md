# Known Limitations & Deferred Work

This is the honest inventory. If you're thinking "wait, does it really do X?" — check here before assuming yes.

Last updated: 2026-04-20, after Phase 7.

## Real gaps (should be fixed before shipping)

### Inference hasn't been validated end-to-end in the real app
The standalone `mlx-probe` Swift package loads Gemma 4 E2B from a local directory and produces output — that proves MLX + the model format + the model config we pass are correct. But **no one has yet clicked through the deployed Eidos app and watched Gemma stream a response into the chat bubble**. The two times we tried:
- iOS Simulator — MLX crashes in C++ because simulator Metal can't run custom shaders.
- Mac (Designed for iPad) — sandbox blocks the pre-downloaded `/Users/.../eidos-models/` path we used to side-load. We fixed this by copying the model into the app's sandbox container.

Next step: a real iPhone 13+ run. Full checklist in `masterplan.md` Phase 2d.

### No real Share Extension
The target exists (`EidosShareExtension`) with correct `NSExtension` plist entries. The `ShareViewController` is scaffolded but doesn't actually parse incoming payloads and write them to the App Group queue. `AppGroupStore` has the helpers ready. Adding this requires:
- Setting up an App Group (`group.com.eidos.shared`) with an Apple ID, which means the free Personal Team has to be upgraded to a paid developer account.
- Adding the `com.apple.security.application-groups` entitlement to both targets.
- Wiring `ShareViewController` to extract `NSItemProvider`s and write `PendingIngestionItem`s.

Until then, imports go through the Ingest tab's manual paste UI.

### No App Intents / Shortcuts / Spotlight integration
Phase 5.4. Each skill would need `AppIntent` conformance plus parameter struct mirrors. Decent setup cost, deferred for a dedicated session.

### No routine learning
Phase 6.1. Detecting patterns over calendar/location/health requires months of accumulated data. The *infrastructure* to ingest those signals is in place (CalendarSource, HealthSource, MemoryManager) — the actual pattern-detection pass is deferred until there's real usage data to learn from.

### No life-logging / ambient day-shape
Phase 6.4. Nightly crystallization across calendar + health + locations needs a BackgroundTasks registration and a longer Gemma call chain. Deferred.

### No tone engine
Phase 6.5. Learning how the user writes to different contacts requires a corpus of their messages — which requires Share Extension ingestion of WhatsApp/Mail. Unlocked by 5.2.

### No relationship intelligence
Phase 4.3. Contact-level communication signals (how often, last interaction, important dates) would need message ingestion first. Deferred with 5.2/6.5.

### No Widget / Live Activity
The Home digest has structured `ProactiveSignals` ready for a widget timeline, but no widget target yet.

## Soft limitations (known but acceptable for now)

### EgressGuard is advisory for the HuggingFace download path
`URLProtocol.registerClass` only applies to sessions using the default configuration. The `swift-huggingface` client creates its own URLSession and bypasses the guard. We observed this empirically during Phase 2 debugging. Our own `HuggingFaceDownloader` (which we ship with) DOES use `URLSession.shared`, so the guard applies there. For production privacy-hardening we'd need to either:
- Swap out `swift-huggingface` for our own downloader entirely (partially done; the macro-based loader still uses it)
- Or pin HTTPS certificates on every client and audit transitively

### Gemma 4 E2B is a multimodal model
The config declares `Gemma4ForConditionalGeneration` with an `audio_config` section. We use MLXLLM which only exercises the text path (`Gemma4TextModel`). That works, but it means we're carrying 1.5 GB of weights for capabilities we don't use. A text-only variant would be cheaper, but mlx-community hasn't published one.

### Conversation history has no browser
We persist conversations to SwiftData (`Conversation`/`ConversationMessage`) and the chat view auto-resumes the most recent one. But there's no UI to browse past conversations, search them, or delete them. Memory crystallization captures the important bits at session end, so this is lower priority — but worth building for trust.

### No metrics / observability
We don't track tokens/sec, RAM peak, retrieval-quality signals, or error frequencies. Even a Settings-only debug panel would be valuable. Right now debugging happens by attaching Xcode.

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

- 120+ unit/integration tests, all passing on iPhone 17 simulator
- Swift 6 strict concurrency compliance (no warnings)
- `BUILD SUCCEEDED` for iOS simulator with `-skipMacroValidation`
- Standalone `mlx-probe` confirms Gemma 4 E2B loads and generates text on macOS

## What we haven't tested

- A real iPhone running the deployed app
- Airplane-mode inference (the EgressGuard validation)
- Memory behavior over weeks/months of usage
- Thermal behavior under sustained generation
- Notification scheduling across reboots / background app refresh interactions
- HealthKit queries against real data (we have the code; no live data in our test env)
- The share extension (scaffold only)

## Tests at time of writing

120 tests across:
- `SkillParserTests`, `TextChunkerTests`, `VectorStoreTests`, `RRFusionTests` (Phase 1)
- `EgressGuardTests`, `PromptTemplatesTests` (Phase 2)
- `MemoryManagerTests`, `MemoryIndexTests`, `MemoryDecayEngineTests`, `MemoryCrystallizerTests`, `ContextBuilderTests`, `RAGIntegrationTests` (Phase 3)
- `SkillsTests` (Phase 4)
- `AppActionTests`, `ImporterTests` (Phase 5)
- `HealthInsightTests`, `NotificationSchedulerTests` (Phase 6)
