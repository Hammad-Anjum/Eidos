# Eidos — On-Device AuDHD Companion

> Submission to the **Kaggle Gemma 4 Good Hackathon** (deadline
> 2026-05-18). Track: **Digital Equity** (with overlap into Health &
> Sciences for the RSD / burnout safety angle).
>
> An iOS app for AuDHD adults — the autism + ADHD overlap — that
> looks at your mess and tells you where to start, grounds you when
> criticism stings, listens when you ramble, and never asks you to do
> executive function to use it. **No byte ever leaves your phone.**

## The problem

There are ~1.5M+ members on r/ADHD, ~2M+ across r/autism and
r/AutismInWomen, and a fast-growing r/AuDHD community for adults
discovering they're both. They drop apps fast: per RevenueCat and
follow-up Wellnest research, **54% of ADHD users drop apps within
weeks** — the apps demand the exact executive function the user
lacks.

The existing market fails the AuDHD adult specifically:

- **Tiimo** ($54/yr, 2025 App Store App of the Year) is beautiful at
  visual planning but **doesn't help when planning has already
  failed**.
- **Goblin Tools** is free and viral, but cloud-routed — your messy
  task list goes to OpenAI.
- **Inflow** ($95/yr) ships CBT modules and a coach feel; rejection-
  sensitive users find structured planning content defeating.
- **Saner.AI** ($8-20/mo) is cloud chat.
- **Spoons** ($79/yr) gets the design philosophy right (offline, no
  gamification, autistic-built) but is a single-purpose energy
  tracker — not a companion.

Apple's Siri 2.0 partnered with Google Gemini in early 2026, so even
the "system AI" voluntarily forfeited the pure-on-device privacy
claim. **Data brokers actively sell ADHD / depression / autism
diagnosis lists** ($2,500 for a depressed-individuals list with names
+ addresses per IDX research); insurance underwriters use them. The
AuDHD adult walks in already knowing they don't want their burnout
log shipped to OpenAI.

## What it does

Four flows, all voice-first or camera-first, all on-device:

| Flow | When you'd use it | What happens |
|---|---|---|
| **Look** | Looking at a cluttered desk / inbox / chore list | Tap camera. Photo. Gemma 4 vision narrates a spoken 3-step plan with a 5-minute commitment. |
| **Ground** | Just got criticized; spiraling; can't think | Voice in. Eidos returns a scripted grounding response (5-4-3-2-1 sensory cue, breath cue, one physical action). It does NOT ask "do you want to talk about it." |
| **Journal** | Need to get a hard conversation or feeling out of your head | Tap mic. Ramble. Stop. Eidos crystallizes the rambling into tagged memory entries you can find later. |
| **What Now** | "I have fifteen things and my brain stopped." | Voice in. Eidos asks your energy (0-4). Picks ONE task from your calendar + memory. Returns a 5-minute commitment script. Not a list. One thing. |

Plus a system-prompt default tone shaped to AuDHD inertia: short
replies, one option, slow pacing, never moralizing, never
"shoulds." Spoons-style energy slider on Home; Settings toggle to
flip to ADHD-only or autistic-only mode (adapts the prompt + UI).

## Why Gemma 4

This submission shows three of Gemma 4's distinctive features visibly:

| Feature | Where in the flow |
|---|---|
| **Multimodal vision** | The "Look" flow — point the camera at your real mess, Gemma processes the image on-device. |
| **Native function calling** | "Look" and "What Now" both emit structured tool calls. iOS sees a real action, not a chat reply. |
| **Multilingual reasoning** | Apple's on-device speech in 50+ languages combines with Gemma's multilingual reasoning. Spanish "Look", Arabic "Ground" — same flow, same model, same device. |

Variant: **Gemma 4 E2B** (4-bit, 1.5 GB) via MLX Swift. Vision through
`MLXVLM`. Inference fully on-device.

## Privacy posture

- **`EgressGuard`** — a `URLProtocol` subclass installed at app launch
  blocks all outbound traffic except the one-time Gemma 4 model
  download. After bootstrap, the network is dead in code, not just in
  policy. Verified via `tcpdump` in the technical write-up.
- **Biometric app lock** with privacy-snapshot overlay so iOS's
  app-switcher cache cannot capture journal content.
- **Markdown audit log** of every memory entry — exportable,
  user-editable, never synced.
- **No telemetry, no analytics, no third-party SDKs.**
- **`SafetyGate`** intercepts actual crisis language pre-LLM with
  hardcoded resources (988 in US, 911/112 emergency). Grounding flow
  is for non-crisis RSD — SafetyGate doesn't fire here, Gemma's
  scripted response handles it.

## What this app explicitly is not

- Not a therapist, not a coach, not a productivity app.
- Not a diagnostic tool. Self-identification only.
- Not gamified. No streaks, no badges, no virtual pet.
- Not a planner. (Tiimo + Apple Reminders cover that.)
- Not a "you should journal more" nag. It's there when you need it
  and silent the rest of the time.

## Repository layout

```
Eidos/
  App/                      # Bootstrap, DI, AppIntents
  Inference/                # GemmaSession + MLX wrapper, prompt templates
  Memory/                   # Markdown source-of-truth memory + decay + recall
  KnowledgeBase/            # Substrate
  Embedding/                # NLContextualEmbedding bridge
  RAG/                      # ContextBuilder + RAGPipeline (tool-call loop)
  Skills/                   # Tool-call substrate (AuADHD skills land next session)
  Platform/                 # Camera + speech + audio capture; SafetyGate;
                            # EgressGuard; AppLock; Diagnostics
  UI/                       # Home (4 voice-first tiles), Chat, Memory, Settings
  Resources/                # Info.plist, entitlements
EidosShared/                # App-Group bridge for widget data
EidosWidget/                # Control Widget entry points
project.yml                 # xcodegen source
```

## Build

Requires macOS, Xcode 17+, iOS 26 SDK, and `xcodegen`.

```bash
brew install xcodegen
xcodegen generate
open Eidos.xcodeproj
```

Run on iPhone 15 Pro or later for production multimodal performance.
Mac (Designed for iPad) runs the full Gemma pipeline natively. The
iOS Simulator falls back to canned inference responses (MLX Metal
crashes inside the simulator).

**Demo-day note**: flip `minimalChatPromptEnabled` OFF in Settings →
Diagnostics → Flags before recording. Tool calling depends on it.

## License + acknowledgments

- **Eidos source**: MIT (see `LICENSE`).
- **MLX Swift**: Apache-2.0.
- **Gemma 4 model weights**: governed by Google's
  [Gemma Terms of Use](https://ai.google.dev/gemma/terms).
- **No third-party content bundled**. The RSD / grounding script is
  derived from public 5-4-3-2-1 and breath-pacing patterns used in
  CBT / DBT — common knowledge, not licensed material.

For the live product spec, see [`PRODUCT.md`](PRODUCT.md).
For working rules in this repo, see [`CLAUDE.md`](CLAUDE.md).
