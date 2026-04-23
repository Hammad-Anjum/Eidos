# Eidos

**The on-device AI that does what Siri can't** — remembers everything, acts on your behalf, and never leaks your data.

Eidos is a native iOS personal assistant built around a strict on-device constraint: **after the one-time model download, zero bytes leave your phone**. No cloud inference, no telemetry, no analytics, no sync. The knowledge you feed it — notes, voice memos, calendar, contacts, imported messages, health signals — lives and stays on the device it was captured on.

The agent is powered by **Gemma 4** running through **MLX Swift** on Apple Silicon, with retrieval over a **tiered memory system** that persists across sessions and decays like human memory. Thirteen built-in skills can read state (calendar, reminders, contacts, KB) and perform actions (WhatsApp, SMS, email, calls, navigation, rides) — every outbound action confirmed before dispatch.

---

## What defines this codebase

- **Native iOS, not cross-platform.** Pure Swift 6 + SwiftUI + SwiftData. No React Native, no Flutter, no web views. Every framework is the Apple one that was built for the job.
- **Strict concurrency, enforced.** Swift 6 strict concurrency is on for every target. `@Model` objects never cross actor boundaries — all background work hands off via `PersistentIdentifier` through `@ModelActor`.
- **Privacy as a property, not a promise.** `EgressGuard` registers a `URLProtocol` subclass that blocks outbound traffic at the `URLSession` layer. The limitation is documented openly rather than hidden — see [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).
- **Memory that behaves like memory.** Not a flat vector store. Markdown files on disk, tiered P1–P5 (core identity → active → topic → recent → archive), with automatic decay and end-of-session crystallization that consolidates transient context into longer-lived entries.
- **Hybrid retrieval.** Vector search via Apple's built-in `NLContextualEmbedding` (Neural Engine, no bundled weights) merged with keyword search through Reciprocal Rank Fusion. Exact-match queries and semantic queries both work.
- **Agentic with a safety rail.** The model can call tools natively, but every App Action (message, call, navigate, ride) routes through `ActionConfirmationSheet` before dispatch. Nothing sent silently.
- **Honest about scope.** Features that aren't done are in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md), not hidden in docs. The product makes no claim it can't back up.

---

## How Eidos thinks

```
                     ┌───────────────────────────────┐
                     │          ChatView             │
                     └──────────────┬────────────────┘
                                    │  user turn
                        ┌───────────▼────────────┐
                        │      RAGPipeline       │
                        │  (single-pass, tool-   │
                        │   calling native to    │
                        │   Gemma 4)             │
                        └───────────┬────────────┘
                                    │
          ┌─────────────┬───────────┼───────────┬──────────────┐
          │             │           │           │              │
   ┌──────▼──────┐ ┌────▼─────┐ ┌───▼───┐ ┌─────▼─────┐ ┌──────▼──────┐
   │  Knowledge  │ │  Memory  │ │ Skill │ │  Gemma 4  │ │  Platform   │
   │ Repository  │ │ Manager  │ │ Registry│ │ (MLX)    │ │  Sources    │
   │  (SwiftData │ │ (Markdown│ │  (13   │ │ streaming │ │  (EventKit, │
   │  + vectors) │ │  P1–P5)  │ │  tools)│ │  AsyncSeq │ │  HealthKit, │
   │             │ │          │ │        │ │           │ │  CNContacts,│
   │             │ │          │ │        │ │           │ │  Location,  │
   │             │ │          │ │        │ │           │ │  Motion,    │
   │             │ │          │ │        │ │           │ │  Music,     │
   │             │ │          │ │        │ │           │ │  Focus)     │
   └─────────────┘ └──────────┘ └────────┘ └───────────┘ └─────────────┘
```

- **Retrieval** pulls from both the SwiftData-backed `KnowledgeRepository` (notes, imports, web clips) and the markdown-backed `MemoryManager` (tiered persistent memory). `KnowledgeAggregator` merges them.
- **Context building** formats hits for the prompt with source-aware snippet windows and a hard character cap so retrieved text can't blow through the model's context.
- **Inference** is one streaming pass through MLX's `ModelContainer` running Gemma 4 E2B. The model decides per-turn whether to emit a tool call via native function-calling tokens.
- **Skill dispatch** parses the structured output, routes to the `SkillRegistry`, and for any action that touches the outside world (WhatsApp, SMS, email, calls, navigation, rides) surfaces an `ActionConfirmationSheet` before firing.
- **Memory writes** happen in the background via `KnowledgeBackgroundActor` (for KB) and `MemoryCrystallizer` (for memory consolidation at end of session).

---

## What Eidos can do

| Surface | Behavior |
|---|---|
| **Chat** | Gemma 4 E2B streaming responses, memory- and KB-aware context, conversation persistence across launches |
| **Voice** | Mic button in chat bar. `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` |
| **Memory** | Tiered MD-file store (P1–P5: core_identity, active, topic, recent, archive) with automatic priority decay and end-of-session crystallization. Full browser UI. Export to zip via Files app |
| **Knowledge base** | SwiftData-backed entries with vector + keyword hybrid search (RRF, k = 60). Browse, edit, delete |
| **Skills** | 13 built-in: calendar read/write, reminders read/create, contacts search, KB search/add, digest, WhatsApp, SMS, email, call, navigate, ride (every action behind a confirmation sheet) |
| **Home** | Morning briefing combining calendar, reminders, memory highlights, and HealthKit insights. Daily notification at a configurable time |
| **Widget** | Live Activity showing the daily briefing on the lock screen and Dynamic Island |
| **Shortcuts** | Apple Intents integration — trigger Eidos from Siri, voice, or the Shortcuts app |
| **Settings** | Model status, notification time, HealthKit permission, decay pass trigger, storage counts |

---

## Privacy architecture

Eidos has a hard **no-egress** stance. After the one-time model download:

- **`EgressGuard`** registers a `URLProtocol` that intercepts outbound requests and blocks anything not on the HuggingFace allowlist (and only during an explicit model download window).
- **On-device speech recognition** (`requiresOnDeviceRecognition = true`) — audio and transcripts never hit a server.
- **HealthKit** read access is optional; insights are stored, raw samples never are.
- **Memory files** live in the app sandbox Documents directory, never synced, never uploaded.
- **`.completeFileProtection`** on the SwiftData store and App Group queue — readable only when the device is unlocked.

### Honest scope of `EgressGuard`

`URLProtocol.registerClass` only affects sessions that respect URL protocols — which is `URLSession.shared` and `URLSession(configuration: .default)`. The HuggingFace Swift client uses its own `URLSession` configuration, so the guard doesn't block it during model download (the only traffic we want anyway). Our `HuggingFaceDownloader` uses `URLSession.shared`, so the guard applies to it. For production hardening we'd pin HTTPS certificates and audit every dependency's networking. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for the full gap list.

---

## Project layout

```
Eidos/
  App/                    # @main, container, tab router, feature tour
    AppIntents/           # Apple Shortcuts / Siri integration
  Inference/              # MLX Swift session, HF downloader, prompt templates
  Embedding/              # NLContextualEmbedding wrapper, vector store
  KnowledgeBase/          # SwiftData models, repository, background actor
  RAG/                    # ContextBuilder, RAGPipeline
  Memory/                 # Entry, Manager, Index, DecayEngine, Crystallizer,
                          #   Aggregator, Exporter, Frontmatter
  Skills/                 # Tool-calling protocol + 13 built-in skills
  Platform/               # EventKit, Contacts, HealthKit, Speech, Location,
                          #   Motion, Music, Focus, AppAction registry,
                          #   NotificationScheduler, LiveActivityManager,
                          #   EgressGuard
  Ingestion/              # WhatsApp / mail / plain-text importers, coordinator
  Digest/                 # DigestGenerator, ProactiveDigestGenerator
  UI/                     # SwiftUI views & view models
  Resources/              # Info.plist, entitlements
EidosShared/              # Code shared between app and widget
EidosWidget/              # Widget + Live Activity extension
EidosShareExtension/      # Share Extension target (scaffold; real impl deferred)
EidosTests/               # Unit + integration tests (120+)
```

---

## Reference documents

- [masterplan.md](masterplan.md) — active strategic roadmap, phase-by-phase status
- [architecture.md](architecture.md) — canonical type/file/UI spec
- [notes.md](notes.md) — research findings and design constraints
- [research.md](research.md) — exploratory deep-dives (agent loop, vectorless RAG)
- [history.md](history.md) — chronological project record
- [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) — honest inventory of gaps and deferred work
- [SHORTCUTS.md](SHORTCUTS.md) — user documentation for Apple Shortcuts / AppIntents
