# Eidos AuADHD — Execution Playbook

> Branch: `AuADHD`. Latest commit: `ea48a66`. Pushed to `origin/AuADHD`.
> Hackathon deadline: **2026-05-18 23:59 UTC**. Today: **2026-05-14**.
> **4 days. No buffer.**

This file is the canonical execution playbook for the AuADHD Kaggle
submission. It supersedes the 19-day timeline in `PRODUCT.md` (that
budget was set on April 29 and has burned).

## Status snapshot (2026-05-14)

Legend: ✅ done · ⏳ code shipped, validation pending Mac/device · ⬜ not started

| Phase | Status | Commit |
|---|---|---|
| **Phase 1** — VERIFY | ⏳ Mac verify pending (1a, 1b) + reliability sweep pending (1c); fixture code shipped | `eede6ee` |
| **Phase 2** — SKILLS + PROMPT | ✅ All 4 skills + prompt addendum + 4 benchmark fixtures landed | `eede6ee` |
| **Phase 3** — UX | ✅ Home tiles + energy slider + journal mic + dispatch landed; VoiceOver eyes-closed test pending device | `be14a84` |
| **Phase 3.5** — NEGOTIATED ADDS | ✅ Repeat-utterance speaker button + Crisis tile + AuADHD onboarding refresh (3 cards + IdentityStep name/purpose) landed | `72ec6e8` |
| **RAG hotfix** — INDEX-ON-SAVE | ✅ `MemoryManager.onSave` hook + `ContextBuilder` semantic merge + threading wired | `ea48a66` |
| **Phase 4** — POLISH + DEMO | ⬜ Not started (pre-seed data, benchmark sweep, tcpdump audit, demo shoot) | — |
| **Phase 5** — SUBMIT | ⬜ Not started (video edit, write-up, tag, submission) | — |

## RAG hotfix (commit `ea48a66`, 2026-05-14)

Closed two demo-critical bugs surfaced by an audit:

1. **Skills that save memory entries never indexed them into recall**
   (`VoiceJournalCaptureSkill`, `BreakDownSceneSkill`). Fresh entries
   were invisible to semantic recall until the next app launch's
   `rebuildIndex()`. **Demo impact**: the hero ramble→recall clip
   (1:15–1:50 of the script) would have shown "nothing recorded
   about that yet."
2. **`ContextBuilder.gatherMemory()` was rule-based only.**
   `.recentSession` entries (fresh journal, scene breakdowns) were
   never selected for the full chat path's prompt.

Fix landed via:
- `MemoryManager.save(_:reindex:)` + `attachOnSave(_:)` hook.
- `ContextBuilder.memoryRecall: MemoryRecallService?` + semantic
  merge at threshold 0.40.
- `RAGPipeline.init` threads `memoryRecall` into `ContextBuilder`.
- `AppContainer.bootstrap()` wires the hook.

Tradeoff accepted: every save now re-embeds title+body. ~100ms NE
hit per save. Acceptable because saves are user-paced. `touch()`
suppresses the hook (no source-text change). See `CLAUDE.md` →
*Architectural invariants* for the operating contract.

---

## Locked decisions (this session)

1. **Scope**: ship all 4 surfaces + 2 prompt sections.
   Surfaces: Look / Ground / Journal / What Now.
   Prompt sections: AuADHD-default inertia tone + Grounding script.
2. **Demo videographer**: founder solo with VoiceOver + screen
   curtain + eyes-closed protocol. Document the limitation in the
   write-up; no false "tested with the community" claim.
3. **Demo device**: iPhone 15 Pro+ with `minimalChatPromptEnabled`
   OFF. Authentic on-device demo. Accept the OOM risk; film multiple
   takes and pick the one that survives. Mac (Designed for iPad)
   backup take in case all iPhone takes fail.
4. **Mode toggle**: AuDHD-default only in v1. ADHD-only and
   autistic-only modes deferred to v2 (post-hackathon).

---

## Hard ship gates per day (compressed — we're at Day 3)

| Day | Date | Gate | If gate fails |
|---|---|---|---|
| ~~1~~ | ~~May 13 (Tue)~~ | Code-side complete (skills + UX + RAG fix); Mac verify slipped | Mac verify must happen Day 3 or pivot to chatLite-only demo |
| **3** | **May 14 (Wed) — today** | Mac build clean + tool-call reliability sweep ≥85% on `auadhd.scene.tool` | Cut BreakDown + WhatNow from v1; ship Ground + Journal as primary |
| 4 | May 15 (Thu) | Pre-seed demo data + tcpdump audit + 1 clean take per surface | Re-shoot bad takes evening of Day 5; do not extend |
| 5 | May 16 (Fri) | ≥3 of 4 clean demo takes + benchmark sweep JSONL captured | Use the Mac (Designed for iPad) backup take |
| 6 | May 17 (Sat) | Demo video edited + 2-page write-up draft | Submit Day 7 morning at risk |
| 7 | May 18 (Sun) | Repo public + submission landed by 23:59 UTC | **No fallback. Deadline is hard.** |

---

## Phase 1 — Day 1 (May 13) — VERIFY ⏳

### 1a. Mac build verify (~30 min, cofounder) ⬜

```bash
cd ~/path/to/Eidos
git fetch origin
git checkout AuADHD
git pull
xcodegen generate
xcodebuild build -scheme Eidos \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

If build fails:
- Most likely: an orphan symbol or `SwiftData` schema migration warning. Delete simulator data: `xcrun simctl erase all`.
- Patch on top, push. Don't amend `acff63b`.
- If unrecoverable: `git reset --hard origin/medical-helper` resets AuADHD; replay the docs work with the fix.

### 1b. Flip the chat-tool flag ⬜

On the demo iPhone build (and on simulator for testing):

- Settings → Diagnostics → Flags → toggle **"Minimal chat prompt"** OFF.
- Verify Diagnostics → Smoke pane still passes (Gemma generates 4 tokens).
- Verify a test tool catalogue is exposed by checking the prompt log shows `## Available tools` block populated.

This is the **single highest-cost mistake on demo day**. Confirm BEFORE filming.

### 1c. Day-1 reliability sweep — THE GATE ⏳ (fixture code shipped in `eede6ee`; sweep run pending Mac+Gemma)

Add ONE benchmark fixture to `Eidos/Platform/Diagnostics/BenchmarkCorpus.swift`:

```swift
// At top of BenchmarkCategory enum, add:
case auADHD

// In displayLabel switch:
case .auADHD: "AuADHD — surface tool-calls"

// In all-corpus assembly:
prompts.append(contentsOf: auADHD)

// New static array near end of file:
static let auADHD: [BenchmarkPrompt] = [
    .init(id: "auadhd.scene.tool", category: .auADHD,
          prompt: "I'm looking at this and I don't know where to start.",
          needsImage: true,
          expectedMaxSeconds: 30
    ) { out in
        let lower = out.lowercased()
        let hasTool = lower.contains("break_down_scene")
        let hasJSON = lower.contains("\"tool\"") && lower.contains("\"parameters\"")
        if hasTool && hasJSON { return (1.0, "Tool call emitted") }
        if hasJSON           { return (0.5, "JSON but wrong tool")  }
        return (0.0, "Raw narration, no tool call")
    }
]
```

Run **20 iterations** against a real cluttered-desk photo (`Eidos/Resources/test-fixtures/cluttered-desk.jpg`, founder supplies). Capture JSONL output.

**Pass threshold: ≥85% (17/20) emit a `break_down_scene` tool call with valid JSON.**

If 85% < pass < 100%: continue Phase 2 as planned.
If <85%:
1. Retune the Med Mode-style prompt addendum (the Vision section, see Phase 2 below). 4 hours max.
2. Re-run.
3. If still <85% by EOD: **CUT BreakDownSceneSkill and PickNextTaskSkill from v1**. Pivot demo to Ground + Journal + prompt-only patterns. Document the failure honestly in the write-up.

---

## Phase 2 — Days 2-3 (May 14-15) — SKILLS + PROMPT ✅ (commit `eede6ee`)

### 2a. AuADHD addendum to `PromptTemplates.systemPrompt` ✅

Add a new section block in `Eidos/Inference/PromptTemplates.swift` after the "Tool use" section, before "Things iOS does not allow":

```
## Who you're talking to

The user is an AuDHD adult — autism plus ADHD overlap. They drop apps
that demand the executive function they currently lack. Every reply
must respect that.

- Replies stay SHORT by default. One option, not three.
- Never moralize task value ("important", "should", "really need to").
- Never use streaks, badges, or "you missed N days" language.
- "Stuck" not "broken." "The day is heavy" not "your autism is acting up."
- Body-double mode by default: parallel presence, not coaching.

## Visual overwhelm

When the user attaches a photo of a physical scene (desk, room, sink,
inbox screenshot) AND their message contains overwhelm language
("can't start", "where do I begin", "overwhelmed", "too much",
"stuck", "mess") → call `break_down_scene` with the image. Do NOT
describe the scene yourself first; the tool returns the spoken script.

## What now / decision fatigue

When the user says "what should I do" / "what now" / "brain stopped" /
"I have N things" → call `pick_next_task` with `energy_level` (0–4,
ask if unknown). The tool returns ONE pick + a starter script. Read
the script as-is — do not add alternatives or backups; that is the
whole anti-paralysis point.

## Memory recall

When the user references something they "told you before" / "wrote
about" / "mentioned" → call `recall_relevant_memories` with their
phrasing as the query. Do NOT guess from your context window; always
recall.

## Grounding (RSD / overstim)

When the user signals acute emotional dysregulation — phrases like
"spiraling", "can't think", "want to quit", "got criticized",
"everything is loud", "RSD" — do NOT problem-solve, do NOT validate
by minimizing, do NOT diagnose. Run the grounding script:

  1. One sentence acknowledging the sensation (name it, don't fix it).
  2. A 5-4-3-2-1 sensory cue: "name 5 things you can see right now."
  3. A breath cue: "in for 4, hold 2, out for 6 — twice."
  4. ONE small physical action: "stand up, walk to a window."

End there. Do not append "would you like to talk about it." The user
came here to land, not to process.

SafetyGate still intercepts actual crisis language upstream — if it
reached you, you're seeing non-crisis RSD / overwhelm, treat
accordingly.

## What is NOT this app

- Not a therapist. Not a coach. Not a productivity app.
- Crisis language is intercepted upstream. Never attempt diagnosis.
- If the user asks "am I autistic / ADHD" — refuse gently and route
  to a qualified clinician.
```

### 2b. Four new skill files ✅

All four go in `Eidos/Skills/Builtin/`. Each conforms to the `Skill`
protocol; each registers in `Eidos/App/AppContainer.swift` `init()`.

**`BreakDownSceneSkill.swift` (~80 LoC)** — the hero.
```swift
struct BreakDownSceneSkill: Skill {
    let name = "break_down_scene"
    let description = "Parse a photo of a cluttered scene into a 3-step start-here plan with a 5-minute commitment."
    let parametersSchema: String = """
    { "scene_description": "string — what you see; 2-3 sentences",
      "first_action": "string — the single 5-minute action to start with",
      "next_two_steps": ["string", "string"] }
    """
    let memory: MemoryManager
    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let first = parameters["first_action"]?.stringValue,
              !first.isEmpty
        else { return .failure("Couldn't parse a starting step.") }
        let next = parameters["next_two_steps"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        let description = parameters["scene_description"]?.stringValue ?? ""
        // Persist a short memory of the scene for cross-session recall.
        let entry = MemoryEntry(
            tier: .recentSession,
            title: "Scene breakdown — \(String(description.prefix(40)))",
            body: "First: \(first)\nNext: \(next.joined(separator: " | "))",
            priority: .p3,
            tags: ["scene", "look-mode"]
        )
        _ = try? await memory.save(entry)
        var spoken = "Start with: \(first). Five minutes."
        if let n0 = next.first { spoken += " Then: \(n0)." }
        if next.count >= 2     { spoken += " Then: \(next[1])." }
        return .success(spoken)
    }
    func availability() async -> SkillAvailability { .available }
}
```

**`VoiceJournalCaptureSkill.swift` (~100 LoC, as-shipped)** —
bypass-the-Gemma path. Called from the Home Journal tile directly,
not via the chat pipeline. Conforms to `Skill` for symmetry but
invoked imperatively. **Skipped the crystallizer** for v1: voice
journals are saved verbatim as a single `MemoryEntry`
(`tier: .recentSession`, priority `.p3`, tags
`["journal", "journal-YYYY-MM-DD"]`) so the user's words are
preserved exactly. Crystallization can run later on demand.

On save failure (disk-full / permission), the transcript is written
to `FileManager.temporaryDirectory/journal-recovery/<uuid>.md` so
the user's words aren't lost — see `writeRecoveryFile(transcript:tags:)`
in the file. Doc here was previously claiming a
`MemoryCrystallizer.crystallize(messages:tagHint:)` signature that
doesn't exist; the real crystallizer signature is
`crystallize(conversation:defaultTier:defaultPriority:)` and v1
chose not to use it for journal entries at all.

**`RecallRelevantMemoriesSkill.swift` (~50 LoC)** — chat tool.
```swift
struct RecallRelevantMemoriesSkill: Skill {
    let name = "recall_relevant_memories"
    let description = "Find past memory entries semantically similar to a query."
    let parametersSchema: String = """
    { "query": "string — what the user is asking about" }
    """
    let recall: MemoryRecallService
    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let query = parameters["query"]?.stringValue, !query.isEmpty
        else { return .failure("Need a query.") }
        let hits = await recall.recall(query: query, topK: 3, minScore: 0.30)
        if hits.isEmpty { return .success("Nothing recorded about that yet.") }
        let lines = hits.prefix(3).map { "- \($0.entry.title): \($0.entry.body.prefix(120))" }
        return .success(lines.joined(separator: "\n"))
    }
    func availability() async -> SkillAvailability { .available }
}
```

**`PickNextTaskSkill.swift` (~100 LoC)** — decision paralysis.
```swift
struct PickNextTaskSkill: Skill {
    let name = "pick_next_task"
    let description = "Given the user's energy level, pick ONE task from their active priorities + calendar."
    let parametersSchema: String = """
    { "energy_level": "integer 0-4 — 0 burnout, 4 high energy" }
    """
    let memory: MemoryManager
    let calendar: CalendarSource
    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        let energy = parameters["energy_level"]?.intValue ?? 2
        let upcoming = await calendar.fetchEvents(daysAhead: 1)
        let priorities = await memory.index.records(tier: .activePriorities)
        // Heuristic: low energy (0-1) → smallest task; mid (2) → first incomplete;
        // high (3-4) → most-important task by priority.
        let candidates = priorities.sorted { $0.priority.rawValue < $1.priority.rawValue }
        guard let pick = candidates.first else {
            return .success("Nothing on your priority list yet. Start with whatever's bothering you most.")
        }
        let timeHint: String = {
            switch energy {
            case 0...1: return "Just two minutes. Just enough to start."
            case 2:     return "Five minutes. That's the whole commitment."
            default:    return "Ten minutes. Then check back in."
            }
        }()
        var reply = "Start with: \(pick.title). \(timeHint)"
        if let nextEvent = upcoming.first {
            let mins = max(0, Int(nextEvent.startDate.timeIntervalSinceNow / 60))
            if mins > 0 && mins < 90 { reply += " You have \(mins) minutes before \(nextEvent.title)." }
        }
        return .success(reply)
    }
    func availability() async -> SkillAvailability { .available }
}
```

### 2c. Register the four in `AppContainer.swift` ✅

Replace `let skillRegistry = SkillRegistry(skills: [])` with:

```swift
let skills: [any Skill] = [
    BreakDownSceneSkill(memory: memoryManager),
    VoiceJournalCaptureSkill(crystallizer: memoryCrystallizer),
    RecallRelevantMemoriesSkill(recall: memoryRecall),
    PickNextTaskSkill(memory: memoryManager, calendar: calendarSource),
]
let skillRegistry = SkillRegistry(skills: skills)
```

### 2d. Extend BenchmarkCorpus ✅

Add 3 more fixtures to the `auADHD` category beyond the Day-1 hero one:

- `auadhd.whatnow.tool` — voice prompt "I have eleven things and my brain stopped" → expect `pick_next_task` tool call
- `auadhd.recall.tool` — prompt "what did I say about Maya last week" → expect `recall_relevant_memories` tool call
- `auadhd.ground.prompt` — prompt "I just got criticized I want to quit" → expect output containing "name", "see", "breath" or similar grounding markers (no tool call, prompt-section test)

### Phase 2 ship gate ⏳ (pending Mac verify)

- Mac build clean after adding skills
- Each skill fires individually via Diagnostics → Smoke pane (or a one-off DEBUG button)
- AuADHD addendum loaded in system prompt (check chat → first turn → log shows prompt size grew)

---

## Phase 3 — Day 4 (May 16) — UX ✅ (commit `be14a84`)

### 3a. Home tiles ✅ (as-shipped)

The actual implementation in `Eidos/UI/Home/HomeView.swift` uses
SwiftUI `.sheet` / `.fullScreenCover` presentation plus a shared
`ChatLaunchIntent` on `AppContainer` (drained by `ChatView` on its
next render), rather than a router-method indirection. The earlier
draft of this doc named a `router.launchLookFlow(...)` API that was
never built — the sheet pattern is what shipped and is what the
demo paths exercise.

```swift
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
    AuADHDTile(icon: "eye.fill", label: "Look", tint: .blue) {
        // Open camera; on capture, write ChatLaunchIntent with the
        // CGImage + jump to chat tab via .eidosJumpToTab notification.
        showCamera = true
    }
    AuADHDTile(icon: "waveform.path.ecg", label: "Ground", tint: .pink) {
        // Pre-stuff "I'm spiraling. Help me ground." into ChatLaunchIntent
        // and jump tab. ChatView drains the intent and fires send().
        fireGroundIntent()
    }
    AuADHDTile(icon: "mic.fill", label: "Journal", tint: .purple) {
        // Full-screen JournalRecordingView; dispatches the skill
        // imperatively (bypasses Gemma). See VoiceJournalCaptureSkill.
        showJournal = true
    }
    AuADHDTile(icon: "questionmark.bubble.fill", label: "What Now", tint: .orange) {
        // Energy level is read from @AppStorage and embedded in the
        // prompt; PickNextTaskSkill also falls back to the same
        // AppStorage key if Gemma fails to extract energy_level.
        fireWhatNowIntent()
    }
}
```

Each tile gets:
- `accessibilityLabel` (e.g. "Look at the mess")
- `accessibilityHint` (e.g. "Opens the camera. After you take a photo, Eidos describes a three-step plan.")
- Minimum 88-point hit target (twice the standard 44 — AuDHD audience often has motor / tremor traits)

### 3b. Energy slider ✅

Add a Spoons-style 0-4 slider above the tiles:

```swift
@AppStorage("eidos.auadhd.energyLevel") private var energyLevel: Int = 2

Section {
    VStack(alignment: .leading) {
        Text("Energy").font(.headline)
        Slider(value: .init(get: { Double(energyLevel) },
                            set: { energyLevel = Int($0) }),
               in: 0...4, step: 1)
            .accessibilityLabel("Energy level, zero is burnout, four is high")
            .accessibilityValue("\(energyLevel) of 4")
        Text(energyLabel(for: energyLevel)).font(.caption).foregroundStyle(.secondary)
    }
}
```

Where `energyLabel(for:)` returns one of: "burnout", "low", "okay", "good", "high".

### 3c. Voice-journal full-screen mic UI ✅

`Eidos/UI/Journal/JournalRecordingView.swift` (new ~80 LoC):
- Full-screen black background, single large STOP button center-screen
- Tap to start → `SpeechTranscriber.start()` streams text
- Tap STOP → calls `VoiceJournalCaptureSkill.invoke(...)` with the transcript
- Speech synthesizer confirms: "Saved."
- Dismisses back to Home

### 3d. VoiceOver pass ⏳ (accessibilityLabel/Hint/traits in code; eyes-closed test on device pending)

With VoiceOver on + screen curtain on (3-finger triple-tap):
- Navigate Home with one finger swipes — every interactive element should speak its label + hint
- Verify the energy slider reads correctly
- Verify each tile fires its action with double-tap
- Test the journal record view: speak announcements when starting / stopping
- Test the chat tab: streaming text gets announced

### Phase 3 ship gate ⏳ (pending device VoiceOver eyes-closed test)

- Founder closes eyes, opens app, fires all 4 surfaces with no sighted help
- All 4 surfaces complete a round-trip Gemma reply
- Energy slider persists across app re-launches

---

## Phase 4 — Day 5 (May 17) — POLISH + DEMO ⬜

### 4a. Pre-seed demo data ⬜

In `AppContainer.bootstrap()`, behind a DEBUG-only flag, seed memory entries:
```
Memory/active_priorities/
  - Email Maya re: Q3 timeline pushback.md (P2)
  - Move laundry to dryer.md (P3)
  - Schedule annual physical.md (P2)
  - Reply to Dad about Sunday.md (P3)
  - Buy birthday card for Sam.md (P3)
```

These ride along inside the demo build. Strip from Release.

### 4b. Benchmark sweep ⬜

Run the full `auADHD` BenchmarkCorpus 10× per fixture. Capture JSONL:
- Per-fixture pass rate
- p50 / p95 generation latency
- Memory pressure samples

The write-up's "Multilingual + reliability results" table comes from this JSONL.

### 4c. Privacy audit ⬜

On a Mac connected to a real iPhone via USB:
```bash
rvictl -s <iphone-udid>
sudo tcpdump -i rvi0 -w eidos-demo.pcap
```
Walk through all 4 surfaces. Stop tcpdump. Verify pcap shows **only** the initial Gemma 4 model download (HuggingFace) packets pre-bootstrap, and zero outbound during the demo flow.

Save the pcap. Screenshot of "zero packets during flow" goes in the write-up.

### 4d. Demo video shoot ⬜

Per the script in `plans/...` and PRODUCT.md:

| t | shot |
|---|---|
| 0:00-0:15 | Black card → phone, airplane mode visible → app launch |
| 0:15-0:45 | **Hero**: cluttered desk → tap Look → spoken plan |
| 0:45-1:15 | Voice "What now, energy two" → "Move laundry. Five minutes." |
| 1:15-1:50 | Tap Journal → ramble about Maya → save → seconds later in Chat → "what did I say about Maya?" → recalled |
| 1:50-2:20 | Voice "I just got criticized, I want to quit" → grounding script + breath + physical action |
| 2:20-2:45 | Toggle Airplane Mode visibly → re-fire one surface (Look) → still works |
| 2:45-3:00 | Close card with GitHub URL |

**On VoiceOver**: leave VoiceOver ON throughout. The video shows screen-curtain dark with audio narration over founder's voice — strong signal of "this is accessible" without claiming "tested with the community."

**Multiple takes per surface.** Don't rely on one-shot perfection. iPhone with `minimalChatPromptEnabled` OFF carries an OOM risk per take; expect to lose 1-2 takes per surface. Backup: shoot the same surface on Mac (Designed for iPad) as a safety net per surface.

### Phase 4 ship gate ⬜

- ≥3 of 4 surfaces have a clean usable take
- tcpdump pcap shows zero egress
- BenchmarkRunner JSONL captured

---

## Phase 5 — Day 6 (May 18, Sunday) — SUBMIT ⬜

### 5a. Edit demo (morning, 2-3 hours) ⬜

- iMovie / Final Cut: trim, color, add open/close cards
- Add lower-thirds for each surface name + the elapsed Gemma latency on screen ("generated in 8.4s, on-device")
- Upload to YouTube unlisted (Kaggle accepts unlisted YouTube links)

### 5b. Technical write-up (afternoon, 3-4 hours) ⬜

Target 2 pages. Sections:

1. **Problem & audience** (1 paragraph)
2. **Architecture diagram** (text-only or ASCII; reference Gemma 4 E2B + MLX Swift + on-device path)
3. **Gemma 4 features used** — table:
   | Feature | Surface(s) | Code reference |
   |---|---|---|
   | Multimodal vision | Look | `Eidos/Inference/GemmaSession.swift:333` `runGuardedGeneration` + `Eidos/Skills/Builtin/BreakDownSceneSkill.swift` |
   | Native function calling | Look / WhatNow / Recall | `Eidos/RAG/RAGPipeline.swift:498` `runWithToolLoop` |
   | Multilingual reasoning | All four | `PromptTemplates.systemPrompt` + on-device `SFSpeechRecognizer` |
4. **Privacy posture** — `EgressGuard` + tcpdump screenshot + biometric `AppLockController` + markdown audit log
5. **Per-surface reliability table** (from Phase 4b benchmark)
6. **What we explicitly did NOT build** (RSD scripting, transition warnings, HealthKit biofeedback, mode toggles, real-user testing). Honesty wins.
7. **Limitations + roadmap**

### 5c. Repo polish + submission ⬜

```bash
# README pass — link the demo video, refresh build instructions
# git tag the submission build
git tag -a v1.0.0-hackathon -m "Kaggle Gemma 4 Good submission"
git push origin v1.0.0-hackathon

# Make repo public via GitHub UI
# Submit on Kaggle competition page
```

### Phase 5 ship gate ⬜

- **Kaggle confirms submission received** before 23:59 UTC.
- No fallback past this.

---

## Risks + recovery

| Risk | Day | Recovery |
|---|---|---|
| Day-1 reliability test < 85% | 1 | Retune for 4h; if still failing, cut BreakDown + WhatNow skills; pivot demo to Ground + Journal as primary |
| Mac build fails on AuADHD | 1 | Patch on top; if unrecoverable, `git reset --hard origin/medical-helper` and replay |
| iPhone OOMs during demo on every take | 4 | Switch to Mac (Designed for iPad) for the demo recording; document in write-up |
| Memory crystallizer doesn't accept journal tag hint | 2 | Extend `MemoryCrystallizer` with a 10-LoC overload that forces a tag prefix |
| Recall returns empty during Phase 4 take | 4 | Pre-record the journal earlier in the day so embedding index is populated; leave 2 min between journal capture and recall demo |
| VoiceOver focus breaks during streaming | 3 | Add `accessibilityFocus` pinning to the streaming bubble during generation |
| Phase 2 slips past Day 3 | 3 | Cut `RecallRelevantMemoriesSkill` (least demo-visible); recall happens passively via `ContextBuilder` `## What I remember` block |
| Cofounder unavailable for Mac verify | 1 | Use the Mac (Designed for iPad) destination on cofounder's machine remotely, or run the AuADHD branch on a temporary fresh checkout |

---

## What we explicitly do NOT ship in v1

- **No scripting / draft-3-versions surface** — tonally collides with Grounding, depends on the chat-tool path
- **No BGTask transition warnings** — iOS scheduling unreliable
- **No HealthKit biofeedback** — out of scope this turn
- **No multi-step tool chains** — `RAGPipeline.chat` is single-loop
- **No diagnosis features** — SafetyGate intercept territory; user self-identifies in Settings
- **No mode toggle (AuDHD / ADHD-only / autistic-only)** — v2; v1 is AuDHD-default only
- **No real-user testing** — founder solo with VoiceOver, document the limitation
- **No app rename** — Eidos stays Eidos
- **No widget surface** — `EidosWidget` target stays as-stubbed; v2 work

---

## Critical files for this build (in order)

1. `Eidos/Platform/Diagnostics/BenchmarkCorpus.swift` — Day 1 fixture
2. `Eidos/Inference/PromptTemplates.swift` — AuADHD addendum
3. `Eidos/Skills/Builtin/BreakDownSceneSkill.swift` — new
4. `Eidos/Skills/Builtin/PickNextTaskSkill.swift` — new
5. `Eidos/Skills/Builtin/VoiceJournalCaptureSkill.swift` — new
6. `Eidos/Skills/Builtin/RecallRelevantMemoriesSkill.swift` — new
7. `Eidos/App/AppContainer.swift` — register the 4 skills
8. `Eidos/UI/Home/HomeView.swift` — 4 tiles + energy slider
9. `Eidos/UI/Home/HomeViewModel.swift` — energyLevel @AppStorage
10. `Eidos/UI/Journal/JournalRecordingView.swift` — new full-screen mic UI

## Verification end-to-end (Day 4)

```bash
# 1. Build clean
xcodegen generate
xcodebuild build -scheme Eidos -destination 'platform=iOS Simulator,name=iPhone 17'

# 2. Smoke pane in Diagnostics passes (4-token Gemma generation)
# 3. Confirm minimalChatPromptEnabled is OFF
# 4. Open Home with VoiceOver + screen curtain
# 5. Fire each of the 4 tiles; each completes a Gemma round-trip
# 6. Run BenchmarkRunner against auADHD category: ≥85% per fixture
# 7. tcpdump on real iPhone across full flow: zero outbound packets
```
