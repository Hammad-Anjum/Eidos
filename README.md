# Eidos

A fully-local iOS personal AI assistant. Gemma 4 runs on-device via MLX Swift, embeddings come from Apple `NLContextualEmbedding`, persistence is SwiftData, and **zero data leaves the device** after the initial model download.

See [architecture.md](architecture.md) for the full design, [plan.md](plan.md) for the build plan, and [masterplan.md](masterplan.md) for the strategic roadmap. Known gaps and deferred work live in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

## Status

All seven roadmap phases have shipped in scoped form. The roadmap is tracked in `masterplan.md` — each phase notes what made it in vs. what was deferred with a clear reason.

- **0** Scaffolding — ✅
- **1** Persistence + embeddings + hybrid RRF — ✅
- **2** Inference (MLX Swift + Gemma 4) — ✅ (real-device validation pending)
- **3** Memory system + RAG + voice + KB browser — ✅
- **4** Platform sources + skills + home/digest — ✅ (4.3 relationship intel / 4.4 notifications → 6.x deferred)
- **5** App actions + importers — ✅ (5.2 real share ext / 5.4 App Intents deferred)
- **6** Proactive intelligence + HealthKit + notifications — ✅ (6.1 routine learner / 6.4 life log / 6.5 tone engine deferred)
- **7** Polish + tests + ship-readiness — ✅

120+ tests, all passing.

## Build

```bash
brew install xcodegen
xcodegen generate
open Eidos.xcodeproj
```

In Xcode:
1. Blue project icon → **Eidos** target → **Signing & Capabilities** → check **Automatically manage signing** → pick your Personal Team.
2. Same for the **EidosShareExtension** target — same team.
3. Pick a destination: **iPhone 17 (iOS 26)** simulator for UI-only work, **My Mac (Designed for iPad)** for everything-but-the-simulator-can't-run-Metal-ML, or a real iPhone 13+ for the full thing.
4. ⌘R.

> The first build takes 5–15 minutes. Xcode compiles mlx-swift's Metal shaders, swift-syntax, and the rest of the 15-package SPM graph.

> `xcodebuild` on CI needs `-skipMacroValidation` because the `MLXHuggingFaceMacros` package requires explicit trust in the Xcode UI. In Xcode, click "Trust & Enable" when prompted.

## Requirements

- **iOS 17+** (SwiftData, `NLContextualEmbedding`, `@Observable`, `SFSpeechRecognizer.requiresOnDeviceRecognition`)
- **Xcode 16+** with Swift 6 strict concurrency
- **Apple Silicon Mac** for the Metal toolchain needed by MLX (any M1 or later)
- Real **iPhone 13+** for inference testing — the iOS Simulator can't run MLX's custom Metal shaders
- ~**2 GB free** on the device (E2B cached after first download)

## What Eidos can do

| Surface | Behavior |
|---|---|
| **Chat** | Gemma 4 E2B streaming responses, memory- and KB-aware context, conversation persistence across launches. |
| **Voice** | Mic button in chat bar. `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. |
| **Memory** | Tiered MD-file store (P1–P5, core_identity/active/topic/recent/archive) with automatic priority decay and end-of-session crystallization. Full browser UI. Export to zip via Files app. |
| **Knowledge base** | SwiftData-backed entries with vector + keyword hybrid search (RRF, k=60). Browse/edit/delete. |
| **Skills** | 13 built-in: calendar read/write, reminders read/create, contacts search, KB search/add, digest, WhatsApp/SMS/Email/Call/Navigate/Ride (action skills queue a confirmation). |
| **Home** | Morning briefing combining calendar, reminders, memory highlights, and HealthKit insights. Daily notification at a configurable time. |
| **Settings** | Model status, notification time picker, health permission button, decay pass button, storage counts. |

## Privacy

Eidos has a hard **no-egress** stance. After the one-time model download:

- `EgressGuard` registers a `URLProtocol` that intercepts and blocks all outbound requests that aren't to an allowlisted HuggingFace host during model downloads.
- On-device speech recognition (`requiresOnDeviceRecognition = true`).
- HealthKit read access is optional; insights only, never raw samples.
- Memory files live in the app sandbox Documents directory, never synced, never uploaded.

### Honest scope of EgressGuard

`URLProtocol.registerClass` only affects sessions that respect URL protocols — which is `URLSession.shared` and `URLSession(configuration: .default)`. The HuggingFace Swift client uses its own URLSession configuration, so the guard doesn't block it (but during a model download that's the only traffic we care about — and we want it). Our own `HuggingFaceDownloader` uses `URLSession.shared`, so the guard applies to it. For production hardening we'd pin HTTPS certificates and audit every dependency's networking. See `KNOWN_LIMITATIONS.md`.

## Project layout

```
Eidos/
  App/                    # @main, container, tab router, feature tour
  Inference/              # MLX Swift session, HF downloader, prompt templates
  Embedding/              # NLContextualEmbedding wrapper, vector store
  KnowledgeBase/          # SwiftData models, repository, background actor
  RAG/                    # ContextBuilder, RAGPipeline
  Memory/                 # Entry, Manager, Index, DecayEngine, Crystallizer, Exporter
  Skills/                 # Tool-calling protocol + built-in skills (incl. AppActionSkills)
  Platform/               # EventKit, Contacts, HealthKit, Speech, AppAction registry,
                          # NotificationScheduler, EgressGuard
  Ingestion/              # WhatsApp / mail / plain-text importers, coordinator
  Digest/                 # DigestGenerator, ProactiveDigestGenerator
  UI/                     # SwiftUI views & view models
  Resources/              # Info.plist, entitlements
EidosShareExtension/      # Share Extension target (scaffold — real impl deferred)
EidosTests/               # Unit + integration tests (120+)
```

## Testing

```bash
xcodebuild -project Eidos.xcodeproj -scheme Eidos \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation test
```

Tests run on the simulator even though inference doesn't work there — everything we test is pure logic or uses in-memory SwiftData / temp filesystem.

## License

TBD.
