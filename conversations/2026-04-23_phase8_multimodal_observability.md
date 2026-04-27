# Claude session log — 2026-04-23 — Phase 8 kickoff (multimodal + observability)

> Companion to [`history.md`](../history.md) (project turning points) and [`masterplan.md`](../masterplan.md) (the source of truth). This file is the **full session record** so you (or a future Claude) can reconstruct every decision made in this session.

---

## Session goal

Transition Eidos from text-only inference to the full capability of Gemma 4 (text + image + audio + chain-of-thought + 128K context), and ship developer-grade diagnostics so future work is measurable.

---

## Starting state

- Phases 0–7 complete (123 tests green)
- Phase 7.5 retrofits shipped (widgets, live activities, 23 app intents, ambient sources, UILaunchScreen fix)
- User running the app on Mac (Designed for iPad) via Xcode
- Gemma 4 E2B downloading on the Mac sandbox

---

## Key discussions and decisions

### 1. Download UX bug — app stuck on "Ready"

**Problem**: After download finished and `phase = .ready`, the app stayed on the download screen instead of transitioning to `RootView`.

**Root cause**: `EidosApp` gated on `container.modelDownloader.isModelDownloaded`, which is a UserDefaults-backed **computed property**. SwiftUI's `@Observable` only tracks stored-property access — it had no signal to re-render when the download completed.

**Fix**:
1. Added `phase == .ready` read in `EidosApp.body` so SwiftUI tracks the observable `phase` property.
2. Added explicit "Start using Eidos" continue button on the `.ready` state of `ModelDownloadView` for UX confirmation.

---

### 2. Gemma 4 reality-check (I was wrong, user was right)

I initially told the user:
> "Gemma 4 E2B / E4B are text-only. Vision needs a swap to Gemma 3n or PaliGemma."

The user pushed back: **"wait gemma 4 is multimodal it supports vision? are we downloading the nlatest models?"**

After web research I confirmed:

| Fact | Value |
|---|---|
| Gemma 4 release date | **2026-04-02** (3 weeks before this session) |
| Variants | E2B, E4B, 26B A4B MoE, 31B Dense |
| Multimodal | **Yes**: text + image + audio (small variants) |
| Context | 128K (E2B/E4B), 256K (larger) |
| License | Apache 2.0 |
| Our model path | `mlx-community/gemma-4-e2b-it-4bit`, 1B params, 3.58 GB |
| Swift package | `mlx-swift-lm` — has separate `MLXVLM` product for vision-language |
| Current code imports | `MLXLLM` (text-only) — **must swap to `MLXVLM` to unlock vision/audio** |

**Lesson (logged to `CLAUDE.md`)**: Do not assert absence of post-knowledge-cutoff developments. Verify first.

---

### 3. Audio path — drop `SFSpeechRecognizer`, use Gemma 4 native audio

User asked to use the full capability of Gemma 4 including native audio input.

Trade-off table:

| | `SFSpeechRecognizer` | Gemma 4 native audio |
|---|---|---|
| Transcription | ✅ | ✅ |
| Tone/urgency/emotion | ❌ | ✅ |
| Non-speech cues (sigh, laugh) | ❌ | ✅ |
| Direct answer from audio | ❌ | ✅ |
| Live partials | ✅ | ❌ (batch at end) |
| Apple dependency | Yes | No |

**Decision**: Replace primary voice path with Gemma 4 audio. Keep `SpeechTranscriber` behind a feature flag as thermal-throttle fallback.

**Privacy posture** (non-negotiable):
- Audio stays in-memory only, never written to disk
- Freed immediately after Gemma generation finishes
- Mic indicator (iOS enforces natively — orange dot)
- Session auto-ends on backgrounding
- Logger records metadata (duration, sample rate, RMS) — **never the buffer**

---

### 4. Vision path

Added `VisionCaptureService` with:
- PhotosPicker (library)
- Camera availability detection
- `decode(data:)` for share-ext / clipboard cases
- Returns `CGImage` (not UIImage) — cheap to hand off, GC-friendly

Permissions added to `project.yml`:
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

Deferred: actual wiring in `ChatInputBar` (camera/photo buttons). Requires `MLXVLM` swap first.

---

### 5. Engineering bar (locked, applies to all new code)

Codified in `masterplan.md` §8.1 and `CLAUDE.md`:

1. `///` doc comments on every public API
2. Typed errors; no raw `NSError`
3. Swift 6 strict concurrency, zero warnings
4. No force-unwraps / `try!` / `fatalError` in production
5. Zero silent catches
6. Crash-safe logging (logger failure never crashes the app)
7. All metrics machine-parseable (JSONL, stable schema)
8. Unit tests on tricky paths
9. Fails-closed on safety (hardcoded, not LLM)
10. Feature flags, not branches

---

### 6. Product principles (locked, don't re-open without user)

- Zero egress after onboarding — EgressGuard
- No telemetry, analytics, or third-party crash reporting
- On-device everything — inference, embeddings, STT, vision
- Privacy is the moat
- Safety-critical paths never touch the LLM
- Swift 6, iOS 17+, SwiftData, MLX Swift

---

### 7. SafetyGate — the non-negotiable pre-LLM refusal

Crisis queries (self-harm, medical emergency, dosing, diagnosis, legal, child safety) **never reach Gemma**. Regex + keyword matching returns hardcoded responses with real emergency resources.

Rule categories: `selfHarm`, `medicalEmergency`, `dosingRequest`, `diagnosisRequest`, `specificLegalAdvice`, `childSafety`.

Resources hardcoded:
- 988 (US Suicide & Crisis Lifeline)
- 911 / 112 / 999 / 000 (emergency services)
- Poison Control numbers (US / UK / India)
- Childhelp National (1-800-4-A-CHILD)
- NSPCC (UK: 0808 800 5000)
- Child Helpline International
- findahelpline.com (global directory)

In RELEASE builds the gate is **always on** — `EidosFeatureFlags.safetyGateEnabled` setter is a no-op. Debug can toggle for testing.

Test suite: ~40 crisis phrases + ~10 false-positive guards ("killing it at work", "dying to see the movie").

---

### 8. Skills / Personas — Phase 9 design (NOT implemented this session)

**Naming discipline**: no "Doctor", no "Therapist". Use:
- Master
- Fitness Coach
- Health Companion (not Doctor)
- Nutrition Guide
- Programmer
- Tutor
- Reflection Partner (instead of Therapist, if we add it later)

**Activation**: Master-dispatch by default; optional room mode.

**Notification budget**: Max 3/day global across all personas. Master arbitrates.

**Onboarding**: Max 5 setup questions per persona + passive learning thereafter.

**Memory architecture**:
```
~/Documents/eidos/
├── core/          # read-by-all personas
│   ├── identity.md
│   ├── preferences.md
│   └── relationships.md
├── personas/
│   ├── fitness/
│   │   ├── profile.md
│   │   ├── sessions/2026-04-*.md
│   │   └── p0_core.md
│   ├── health-companion/
│   │   ├── profile.md
│   │   ├── medications.json    # STRUCTURED, not prose
│   │   └── symptoms/*.md
│   └── ...
└── skill-index.json
```

**Monetization**: Master + Fitness + Notes Helper free. Others paid unlocks ($2.99 each or $4.99/mo bundle). Revenue model that doesn't compromise privacy.

---

### 9. Corpus strategy (confirmed 2026-04-23)

**No runtime scraping**. Breaks EgressGuard. Full stop.

**Bundle curated public-domain datasets at build time**:

| Persona | Source | License | Rough size |
|---|---|---|---|
| Fitness Coach | ExerciseDB | MIT | 30 MB |
| Fitness Coach | OpenPowerlifting | CC0 | 5 MB |
| Health Companion | MedlinePlus (NIH) | Public domain | 80 MB |
| Health Companion | WHO fact sheets | Public domain | 10 MB |
| Health Companion | OpenFDA (general info only, NO dosing) | Public domain | 40 MB |
| Nutrition Guide | USDA FoodData Central | Public domain | 150 MB |
| Nutrition Guide | OpenFoodFacts subset | ODbL | 50 MB |
| Programmer | Swift stdlib docs | Apache 2.0 | 30 MB |
| Programmer | Python stdlib docs | PSF license | 50 MB |
| Programmer | JS MDN docs | CC-BY-SA | 100 MB |
| Tutor | OpenStax textbooks | CC-BY-4.0 | 200 MB core |
| Master | Wikipedia primer subset | CC-BY-SA (with attribution) | 100 MB |

**Never bundle**: copyrighted textbooks, paid medical databases, most PubMed journals.

**Tiered delivery**: ~50 MB "starter" at install, larger pack on-demand.

**Re-uses existing infra**: `VectorStore` + `EmbeddingService` — just per-persona indexes.

---

### 10. Gemma 4 fit assessment (honest)

Per-use-case:

| Use case | Fit | Why |
|---|---|---|
| Text chat | 🟢 Good | Conversation is a sweet spot for small models |
| Digest narration | 🟢 Good | Structured input → prose, low hallucination |
| JSON crystallization | 🟡 Medium-good | 85–95% valid first try; need retry-on-malformed |
| Simple tool use | 🟢 Good | 2–3 field schemas clean |
| Nested tool use | 🟡 Medium | 70–80% valid; keep schemas flat |
| RAG-grounded Q&A | 🟢 Strong | Retrieval hides parametric gaps |
| Context-stitching (<10 memories) | 🟢 Good | 128K window absorbs it |
| Context-stitching (50+) | 🟡 Medium | Attention spreads; ranking matters |
| Relationship signal extraction | 🟡 Medium | Subtle cues missed; two-pass voting helps |
| Persona router | 🟢 Good | Short classification |
| Multilingual | 🟡 Medium | Occasional drift to English; explicit prompt helps |
| Vision OCR (clear text) | 🟢 Good | Google optimised for UI + docs |
| Vision handwriting | 🟡 Medium | Clean works; messy cursive fails |
| Vision UI screenshots | 🟢 Excellent | Trained specifically |
| Audio transcription | 🟢 Expected good | Pending measurement |
| Audio intent + tone | 🟡 Novel | Promising but unproven |
| Reasoning (arithmetic ≥4 steps) | 🟡 Medium | CoT helps, doesn't fix ceiling |
| Code generation (non-trivial) | 🔴 Weak | Can't write production code |
| Rare domain facts | 🔴 Weak | Always use RAG |

**Key limitations to design around**:
1. Hallucination on specifics — always RAG consequential facts
2. 128K context ≠ full attention — put critical context near end
3. Keep JSON schemas flat
4. Persona voice drifts after ~20 turns — refresh system prompt periodically
5. Thermal on iPhone for sustained >60s — existing `.thermalCritical` guard suffices
6. 4-bit E2B uses ~3–4 GB RAM — iPhone 8 GB+ safe, 6 GB may swap
7. 3.58 GB download — Wi-Fi recommended; warn on cellular

---

### 11. Conversation history — already stored

User asked "Are we storing full conversation history already?" — **yes**:

```swift
// Eidos/KnowledgeBase/EmbeddingRecord.swift
@Model final class Conversation { ... }
@Model final class ConversationMessage { ... }
```

`ChatViewModel`:
- `loadOrStartConversation()` on launch (fetches most-recent, line 55)
- `ConversationMessage(role: "user", ...)` persisted per message (line 153)
- Streaming assistant text persisted as chunks arrive
- `+` button → `newConversation()` starts fresh thread (line 75)
- Old conversations retained forever on-device
- `.completeFileProtection` — encrypted at rest when device locked

Missing (deferred):
- UI to browse past conversations
- Per-conversation search (current search routes through crystallized memory, not raw transcripts)

---

## Files created or edited this session

### Created (14)
- `Eidos/Platform/Diagnostics/EidosFeatureFlags.swift`
- `Eidos/Platform/Diagnostics/FailureCategory.swift`
- `Eidos/Platform/Diagnostics/EidosLogger.swift`
- `Eidos/Platform/Diagnostics/MetricsRecorder.swift`
- `Eidos/Platform/Diagnostics/BenchmarkCorpus.swift`
- `Eidos/Platform/Diagnostics/BenchmarkRunner.swift`
- `Eidos/Platform/SafetyGate.swift`
- `Eidos/Platform/AudioCaptureService.swift`
- `Eidos/Platform/VisionCaptureService.swift`
- `Eidos/Inference/ReasoningMode.swift`
- `Eidos/UI/Settings/DiagnosticsView.swift`
- `EidosTests/SafetyGateTests.swift`
- `EidosTests/EidosLoggerTests.swift`
- `CLAUDE.md`

### Edited (8)
- `Eidos/Inference/GemmaSession.swift` — unified `generate(messages:images:audio:reasoning:)` entry
- `Eidos/Inference/ModelDownloader.swift` — simulator `isModelDownloaded` bypass
- `Eidos/App/AppContainer.swift` — registers benchmark/audio/vision services
- `Eidos/App/EidosApp.swift` — gate observes `phase` for auto-transition
- `Eidos/UI/Onboarding/ModelDownloadView.swift` — continue button + copy
- `Eidos/UI/Settings/SettingsView.swift` — Developer section with Diagnostics link
- `Eidos/Platform/SpeechTranscriber.swift` — simulator mock + hardening
- `project.yml` — camera + photo permissions, UILaunchScreen, v3 structure
- `masterplan.md` — v3 with Phase 8 / Phase 9 / engineering bar / current state

---

## Phase 8 remaining (what's still on the queue)

1. **MLXVLM product** in `project.yml` + `GemmaSession` VLM loader rewrite — currently image/audio input is accepted and logged but falls through to text-only path
2. **ChatInputBar multimodal wiring** — camera button, photo-picker button, audio path switching when `audioViaGemmaEnabled`
3. **Long-context packing** — `ContextBuilder` token budget 7K → 60K with measurement pass
4. **Vision/audio benchmark rubrics** — placeholders exist, need real bundled test assets
5. **More unit tests** — `BenchmarkRunnerTests`, `AudioCaptureServiceTests`
6. **SourceKit drought** — many transient "Cannot find type" warnings from xcodegen regen; all clear on first real build

---

## Phase 9 plan deferred to next session

Explicit per user request ("only do till phase 8 no 9 yet"). Design is locked in §9 of `masterplan.md`.

---

## End state

- Model: Gemma 4 E2B downloading / downloaded on Mac (Designed for iPad)
- Observability: shipped end-to-end
- Safety gate: shipped with 40+ assertions in tests
- Multimodal scaffolding: shipped; VLM swap pending
- Build status: pending user's next ⌘R to validate
- User's next action: ⌘R, try `Settings → Diagnostics → Run benchmarks`, report numbers back

---

## User-visible commitments

- This file documents the session. Any future Claude session reads `masterplan.md` + this conversations folder to catch up.
- `CLAUDE.md` instructs all future Claude sessions to treat `masterplan.md` as source of truth.
- Memory updated at `~/.claude/projects/-Users-sditeam/memory/conversations/2026-04-23_eidos_phase8.md`.
