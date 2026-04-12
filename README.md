# Eidos

A fully-local iOS personal AI assistant. Gemma 4 runs on-device via LiteRT-LM, embeddings come from Apple `NLContextualEmbedding`, persistence is SwiftData, and **zero data leaves the device** after the initial model download.

See [architecture.md](architecture.md) for the full design and [plan.md](plan.md) for the build plan and the architectural deviations from the spec.

## Status

**Phase 0 — scaffolding.** The Swift source tree exists and is authored on Windows. The project has not yet been compiled — that requires macOS.

## Mac handoff

This project is authored on Windows. To build, open it on macOS and run:

```bash
# One-time setup
brew install xcodegen

# Every time project.yml changes
xcodegen generate

# Phase 2 only (TBD — see Podfile)
# pod install   # if LiteRT-LM ships as a CocoaPod
# or add LiteRT-LM via SPM in Xcode

open Eidos.xcworkspace   # (or Eidos.xcodeproj if no Podfile)
```

Then in Xcode:

1. Select the `Eidos` target → Signing & Capabilities → set your Development Team
2. Add the **App Groups** capability to BOTH the `Eidos` and `EidosShareExtension` targets, using the group ID `group.com.eidos.shared`
3. Build and run on Simulator (for UI sanity) or a physical iPhone 13+ (for real inference testing)

## Requirements

- iOS 17+ (SwiftData, `NLContextualEmbedding`, `@Observable`)
- Xcode 16+ (Swift 6 strict concurrency)
- Physical iPhone 13 or later for meaningful inference testing — the Simulator has no Neural Engine
- ~3 GB free disk space for the Gemma 4 E4B model (~1.5 GB for E2B)

## Project layout

```
Eidos/                    # Main app target
  App/                    # @main, container, router
  Inference/              # Gemma/LiteRT-LM session, download, prompts
  Embedding/              # NLContextualEmbedding wrapper, vector store
  KnowledgeBase/          # SwiftData models, repository, background actor
  RAG/                    # Retrieval + generation pipeline
  Skills/                 # Tool-calling protocol and built-in skills
  Platform/               # EventKit, Contacts, Speech, App Group, egress guard
  Ingestion/              # Share Extension queue processor, importers
  Digest/                 # Morning briefing generator
  UI/                     # SwiftUI views and view models
  Resources/              # Info.plist, entitlements

EidosShareExtension/      # Share Extension target
EidosTests/               # Unit test target
```

## Privacy

Eidos is built with a hard no-egress constraint. The only network activity is a one-time model download from Hugging Face, gated through a custom `URLProtocol` allowlist (`EgressGuard`) that blocks all other outbound traffic. See [plan.md §B14](plan.md) for the auditability details.
