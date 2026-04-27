# Eidos — Engineering Notes

Living document of research findings, constraints, and active decisions that inform the build. Updated as we learn things. Read alongside [architecture.md](architecture.md) (canonical spec) and [plan.md](plan.md) (active build plan).

---

## Latest Updates

### 2026-04-12 — Phase 2 pivot: MLX Swift, not LiteRT-LM

Phase 2 was originally planned around LiteRT-LM (Google AI Edge). Research today turned up a hard blocker:

> **LiteRT-LM v0.10.1** ships stable APIs for **Kotlin, Python, and C++ only**. Swift status is "🚀 In Dev" — explicitly noted in the README's supported-language table. No release date.
>
> Source: [google-ai-edge/LiteRT-LM README](https://github.com/google-ai-edge/LiteRT-LM/blob/main/README.md)

We pivoted to **MLX Swift** (`mlx-swift` + `mlx-swift-examples`) — Apple's first-party on-device ML framework. Stable Swift API today, SPM distribution, native Metal/Apple Silicon execution, working iOS reference apps shipped by Apple's ML team. Gemma 4 lives at `mlx-community/gemma-4-E2B-it-4bit` and `mlx-community/gemma-4-E4B-it-4bit` in MLX-compatible format.

Plan §A1 has been revised to reflect this. The `Podfile` will be deleted in Phase 2.0 — MLX is SPM-only.

### 2026-04-12 — NLContextualEmbedding asset download conflicts with EgressGuard

`NLContextualEmbedding.requestEmbeddingAssets()` downloads from Apple's CDN on first launch. This is a second network exception beyond the Gemma model download. Resolved by §A3-asset: `EgressGuard.install()` moves out of `EidosApp.init()` into `AppContainer.bootstrap()`, after `EmbeddingService.ensureAssetsAvailable()` and the model download complete. Implemented in Phase 1.

---

## Implementation Research

### Inference: MLX Swift

**Why MLX over LiteRT-LM**:
- Stable Swift API, today
- SPM distribution (no Bazel, no CocoaPods, no source build)
- Apple-maintained, announced via [swift.org blog](https://www.swift.org/blog/mlx-swift/)
- Working iOS reference apps in `mlx-swift-examples/Applications/`: `LLMBasic`, `LLMEval`, `MLXChatExample`
- Token-by-token streaming via `AsyncThrowingStream` — matches the API shape we already designed
- Models loaded by Hugging Face ID directly (no manual URL/SHA management)
- Native Metal execution on Apple Silicon

**Key dependencies**:
- `github.com/ml-explore/mlx-swift` — core MLX Swift bindings
- `github.com/ml-explore/mlx-swift-examples` — `MLXLLM`, `MLXLMCommon`, `LLMModelFactory`, plus reference apps. Pulls in `mlx-swift` transitively.

**Reference code path** (canonical: `mlx-swift-examples/Applications/LLMEval/LLMEval/ContentView.swift`):

```swift
import MLX
import MLXLLM
import MLXLMCommon

// Load
let configuration = ModelConfiguration(directory: URL(filePath: modelPath))
let modelContainer = try await LLMModelFactory.shared.loadContainer(
    configuration: configuration
)

// Generate (streaming)
try await modelContainer.perform { context in
    let input = try await context.processor.prepare(input: .init(prompt: prompt))
    let stream = try MLXLMCommon.generate(
        input: input,
        parameters: .init(),
        context: context
    )
    for await event in stream {
        if case .chunk(let text) = event {
            // yield to caller
        }
    }
}
```

**Open questions to resolve on first Mac build**:
- Exact `mlx-community` model IDs for Gemma 4 (`mlx-community/gemma-4-E2B-it-4bit` is best-guess from search; verify by browsing the org)
- Function-calling API surface — `LLMEval` mentions "tool integration" but exact signature unknown until source review
- `Hub` snapshot API entry point for `ModelDownloader` (probably `mlx-swift-examples/Libraries/MLXLMCommon`)

### LiteRT-LM Swift status (blocked path)

Documented for the record so we don't re-research it later.

| Language | Status (v0.10.1) |
|---|---|
| Kotlin | ✅ Stable |
| Python | ✅ Stable |
| C++ | ✅ Stable |
| **Swift** | **🚀 In Dev** |

Source: [google-ai-edge/LiteRT-LM README](https://github.com/google-ai-edge/LiteRT-LM/blob/main/README.md)

If Swift bindings ship in a future LiteRT-LM release, we could re-evaluate, but MLX is sufficient and Apple-aligned. No reason to switch back unless MLX hits a blocker.

### Embeddings: NLContextualEmbedding (iOS 17+)

Apple's built-in BERT-based contextual sentence embedding. Used in Phase 1 as `EmbeddingService`.

```swift
let emb = NLContextualEmbedding(language: .english)
if !emb.hasAvailableAssets {
    try await emb.requestEmbeddingAssets()    // hits Apple CDN
}
try emb.load()
let result = try emb.embeddingResult(for: text, language: .english)
result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
    // vector is [Double] of length emb.dimension
    return true
}
```

- Output is per-token. We mean-pool + L2-normalize for sentence vectors.
- Asset download is a one-time CDN hit on first launch — handled in §A3-asset.
- Dimension is determined at load time (`emb.dimension`), not a compile-time constant.

### SwiftData @ModelActor (Phase 1)

The `@ModelActor` macro synthesizes:
- `init(modelContainer: ModelContainer)`
- `nonisolated let modelContainer: ModelContainer`
- `let modelExecutor: any ModelExecutor`
- `let modelContext: ModelContext` (bound to this actor)
- `subscript<T>(id: PersistentIdentifier, as: T.Type) -> T?`

**Critical rule**: `@Model` classes are NOT `Sendable` and must never cross actor boundaries. The Sendable handoff is `PersistentIdentifier` — pass the ID, re-fetch the model on the target actor.

Source: [Apple Developer Forums thread on SwiftData + Sendable](https://developer.apple.com/forums/thread/762178), [BrightDigit ModelActor tutorial](https://brightdigit.com/tutorials/swiftdata-modelactor/), [Hacking with Swift SwiftData concurrency guide](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency).

### Gemma 4 chat template

Search results were vague. Confirmed:
- Standard `system` / `user` / `assistant` roles (per [Function calling with Gemma 4](https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4))
- Native function calling supported on E2B and E4B
- `<|think|>` token for thinking control

Unknown / verify on first Mac build:
- Exact turn delimiter tokens (Gemma 2/3 used `<start_of_turn>` / `<end_of_turn>` — Gemma 4 may differ)
- Exact function-call output token format

**Mitigation**: MLX's `UserInput` accepts message arrays (role + content), so we don't have to hand-format turn tokens. The MLX tokenizer applies the chat template internally. We just provide structured messages.

---

## Design Constraints

Hard constraints that bind future work. Some are physics, some are policy. Check this section before proposing any change to memory budgets, privacy guarantees, or runtime targets.

### Memory budgets per device class

| Device | Total RAM | App-usable (~) | E2B 4-bit (~1.5 GB) | E4B 4-bit (~3 GB) |
|---|---|---|---|---|
| iPhone 13 / 13 mini / 14 / SE | 4 GB | ~2.2 GB | ⚠️ Tight, may OOM under load | ❌ Won't fit |
| iPhone 13 Pro / 14 Pro / 15 / 16 | 6 GB | ~3.5 GB | ✅ Fits comfortably | ⚠️ Tight |
| iPhone 15 Pro / 16 Pro / 17 | 8 GB | ~5 GB | ✅ | ✅ |

**Implication**: `GemmaVariant` must expose a `requiresDeviceClass` field. Onboarding UI hides variants the device cannot run. A 4 GB phone is offered E2B only with no upgrade path. Fall back gracefully if even E2B fails to load on the lowest target.

Sources: [iPhone 13 memory availability — Apple Developer Forums](https://developer.apple.com/forums/thread/702400), [iosref.com RAM by device](https://iosref.com/ram-processor), [How to Run LLMs Locally on Your iPhone in 2026](https://dev.to/alichherawalla/how-to-run-llms-locally-on-your-iphone-in-2026-completely-offline-no-subscription-4b3a).

### Privacy (cumulative across all phases)

- **Zero data egress after onboarding.** Enforced by `EgressGuard` (B14).
- **One-time exceptions**, both during onboarding while `EgressGuard` is **not yet armed**:
  1. NLContextualEmbedding asset fetch from Apple's CDN (~few hundred MB)
  2. Gemma 4 model fetch from Hugging Face (~1.5 GB E2B / ~3 GB E4B)
- **Post-bootstrap**, `EgressGuard` blocks all outbound traffic for the lifetime of the process. The only way to re-open it is for `ModelDownloader` to flip `isModelDownloadInProgress = true` (Settings → Re-download model).
- **All on-device storage** uses `.completeFileProtection` (B6). The SwiftData store, the Share Extension queue file, and any cached files — readable only when the device is unlocked.
- **App Group ID**: `group.com.eidos.shared`.
- **No telemetry, no analytics, no crash reporting.** Anything that would phone home is forbidden by §B14.

### Concurrency (Swift 6 strict)

- Strict concurrency = complete on every target.
- **`@Model` never crosses actor boundaries** (A4). Background work uses `KnowledgeBackgroundActor` + `PersistentIdentifier`.
- `GemmaSession` and `EmbeddingService` are `actor`s; both are `Sendable`.
- `KnowledgeRepository`, `RAGPipeline`, `AppContainer`, all SwiftUI ViewModels are `@MainActor`.
- `Task.detached` is permitted only when capturing `Sendable` values (actors, structs, identifiers) — never `@Model` instances.
- All cross-actor return types must be `Sendable`. SwiftData `PersistentIdentifier` is — `KnowledgeEntry` and friends are not.

### Build & packaging

- **iOS 17.0 minimum.** Required for SwiftData, `@Observable`, `NLContextualEmbedding`, MLX Swift, and `@ModelActor`.
- **Swift 6.0.** Strict concurrency = complete.
- **XcodeGen `project.yml`** is the source of truth for project structure. Hand-editing `.xcodeproj` is forbidden — it generates from YAML.
- **SPM is the only dependency manager.** Podfile is removed in Phase 2.
- **Three targets**: `Eidos` (app), `EidosShareExtension`, `EidosTests`.
- **Bundle IDs**: `com.eidos.app`, `com.eidos.app.ShareExtension`, `com.eidos.app.tests`.

### File system layout (on-device)

- **Gemma model**: `~/Library/Application Support/Models/<huggingfaceID>/` — invisible to the Files app, same on-device guarantees as Documents.
- **SwiftData store**: default container path with `.completeFileProtection`.
- **App Group container** (`group.com.eidos.shared`): used for the Share Extension ingestion queue (`pending_ingestion.json`).
- **NLContextualEmbedding asset**: managed entirely by Apple — we don't see the path, only call `requestEmbeddingAssets()`.

### Testing policy

- **Unit tests for**: pure logic (chunking, RRF, hash, parser), actor surface (vector store math), URL gating (EgressGuard), prompt format snapshots.
- **No mocking of @Model**. Use a real in-memory `ModelContainer` (`isStoredInMemoryOnly: true`) for repository tests.
- **No tests for**: SwiftUI views (visual regression is not worth the cost at this scale), real LLM inference (validated on device, not in CI).
- **Device tests are manual**, run by the Mac collaborator before merging anything that touches `GemmaSession` or `ModelDownloader`.

---

## Open questions / things to verify on first Mac build

1. Exact MLX model IDs for Gemma 4 — confirm `mlx-community/gemma-4-E2B-it-4bit` and `mlx-community/gemma-4-E4B-it-4bit` exist.
2. MLX `Hub` snapshot API entry point and progress callback shape (for `ModelDownloader`).
3. MLX function-calling API surface — does `UserInput` take a `tools:` parameter, or do we prepend tool schemas to the system message?
4. Device class detection — is `UIDevice.current.userInterfaceIdiom` enough, or do we need `Sysctl` for the actual `machine` identifier (e.g. `iPhone14,5`)?
5. NLContextualEmbedding `dimension` property name — verify before Phase 2 doesn't matter, but needed if we ever revisit Phase 1's embedding code.

---

## Source links (researched April 2026)

- [LiteRT-LM README](https://github.com/google-ai-edge/LiteRT-LM/blob/main/README.md)
- [LiteRT-LM Overview — Google AI Edge](https://ai.google.dev/edge/litert-lm/overview)
- [mlx-swift](https://github.com/ml-explore/mlx-swift)
- [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
- [MLXChatExample](https://github.com/ml-explore/mlx-swift-examples/tree/main/Applications/MLXChatExample)
- [LLMEval reference](https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/LLMEval/README.md)
- [On-device ML research with MLX and Swift — Swift.org](https://www.swift.org/blog/mlx-swift/)
- [Function calling with Gemma 4](https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4)
- [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)
- [litert-community/gemma-4-E4B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)
- [Apple — NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [Apple Developer Forums — SwiftData @Model Sendable](https://developer.apple.com/forums/thread/762178)
- [BrightDigit — Using ModelActor in SwiftData](https://brightdigit.com/tutorials/swiftdata-modelactor/)
- [iPhone 13 memory availability — Apple Developer Forums](https://developer.apple.com/forums/thread/702400)
