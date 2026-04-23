# Eidos — Master Plan (v2)

**Last updated**: 2026-04-15
**Vision**: The on-device AI that does what Siri can't — remembers everything, acts on your behalf, and never leaks your data.

---

## What We're Building

An on-device iOS AI personal assistant that:
1. **Remembers** — persistent context across all conversations with priority-based memory
2. **Acts** — controls calendar, reminders, contacts, and hands off to apps via URL schemes
3. **Knows you** — learns your relationships, routines, tone, and preferences
4. **Stays private** — zero data egress after setup, enforced by code (EgressGuard)
5. **Is proactive** — surfaces what you need before you ask (morning digest, relationship nudges)

---

## What's Possible vs. Pushed Back

### POSSIBLE NOW (iOS sandbox allows it)

| Capability | How | Priority |
|-----------|-----|----------|
| Calendar CRUD | EventKit — fully programmatic after permission | P0 |
| Reminders CRUD | EventKit — fully programmatic | P0 |
| Contacts CRUD | CNContacts — fully programmatic | P0 |
| Persistent memory | MD files + SwiftData + sqlite-vec on-device | P0 |
| LLM chat | Gemma 4 E2B/E4B via MLX Swift (~11 tok/s) | P0 |
| Morning digest | Calendar + Reminders + Memory + Weather API (one-time fetch) | P1 |
| Pre-fill messages | URL schemes: whatsapp://, sms:, mailto:, tel: | P1 |
| Pre-fill ride requests | URL scheme: uber://, lyft:// | P1 |
| Pre-fill navigation | URL scheme: maps://, comgooglemaps:// | P1 |
| Voice input | WhisperKit on-device (0.46s latency, 2.2% WER) | P1 |
| Share extension input | Accept text/URLs/files from any app, process locally | P1 |
| Health data insights | HealthKit read (sleep, steps, HRV, workouts) | P2 |
| Smart notifications | UNNotificationCenter — proactive nudges, reminders | P2 |
| Widgets | WidgetKit — pre-computed AI insights on home/lock screen | P2 |
| Live Activities | Real-time status on Lock Screen during active tasks | P3 |
| Spotlight indexing | CSSearchableItem — AI-tagged content in system search | P3 |
| Focus mode response | FocusFilterIntent — adapt behavior per Focus mode | P3 |
| Shortcuts bridge | Ship pre-built .shortcut files for multi-app workflows | P3 |
| App Intents for Siri | Expose Eidos actions to Siri/Shortcuts ecosystem | P3 |

### PUSHED BACK (iOS blocks it — revisit for Android or iOS 19+)

| Capability | Why Blocked | Workaround |
|-----------|------------|------------|
| Send messages without user tap | iOS sandbox — no programmatic send | Pre-fill + user confirms (1 tap) |
| Auto-answer phone calls | CallKit only manages VoIP, not cellular | Build VoIP layer OR rely on iOS accessibility setting |
| Read other apps' screens | No cross-app accessibility API on iOS | Vision model on screenshots (only YOUR app's screen) |
| Tap buttons in other apps | No accessibility service like Android | URL schemes + Shortcuts |
| Continuous background agent | Background execution limits (30s-minutes) | BGProcessingTask during charging + smart notifications |
| Auto-book rides without confirmation | URL scheme opens Uber, user must confirm | Pre-fill everything, one-tap confirm |
| Full email send without UI | MFMailComposeViewController requires user tap | Pre-compose, one-tap send |
| Detect foreground app | No API for this | Irrelevant if we use Shortcuts triggers instead |

### ANDROID-FIRST FEATURES (build when Android version starts)

| Capability | Android Approach |
|-----------|-----------------|
| Full app control | AccessibilityService — read UI tree, click/type/swipe |
| Auto-send messages | AccessibilityService + Intent system |
| Auto-answer calls | AccessibilityService + Telecom framework |
| Continuous background agent | Foreground service |
| Screen reading | AccessibilityService or screenshots + vision model |

---

## Feature Recommendations (Blue Ocean Opportunities)

These are features that the market wants but nobody delivers well. Each is buildable on iOS.

### 1. PROACTIVE INTELLIGENCE (Killer Differentiator)

**What**: Eidos surfaces what you need BEFORE you ask. Not a chatbot waiting for input — an assistant that thinks ahead.

**How it works**:
- Morning digest: Calendar + reminders + relationship nudges + weather + commute + health (sleep quality) + pending follow-ups
- Pre-departure alerts: "You have a meeting at 2pm in Financial District. Uber typically takes 25 min from here. Want me to prepare a ride at 1:30?"
- Follow-up detection: "You told Sarah you'd send her that article. It's been 3 days."
- Pattern alerts: "You usually order groceries on Sundays. Want me to prepare your list?"

**Why nobody does this**: Requires persistent memory + calendar + contacts + routine learning. Siri promised it but delayed to 2027. Samsung/Lenovo doing it on Android only and cloud-based.

**iOS implementation**: BGProcessingTask generates digest during charging → stored as pre-computed widget timeline → notification at wake time → Live Activity for time-sensitive items.

### 2. RELATIONSHIP INTELLIGENCE (Personal CRM That Doesn't Feel Like a CRM)

**What**: Eidos quietly tracks your relationships and helps you be a better friend/colleague/family member.

**Features**:
- "You haven't talked to Mom in 12 days" (based on call/message frequency from Contacts + Calendar)
- Remember details: "Sarah is allergic to nuts, prefers window seats, birthday is March 15"
- Pre-meeting briefing: "Meeting with Alex in 30 min. Last time you discussed the Q2 launch. He mentioned his daughter's recital."
- Relationship health score: communication frequency trend per contact
- Gift/occasion tracker: birthdays, anniversaries, important dates from core memory

**Why nobody does this**: Existing personal CRMs (Monica, Clay, Dex) are manual, web-based, and feel transactional. Nobody does passive, on-device relationship intelligence with zero data egress.

**iOS implementation**: CNContacts for base data + EventKit for interaction signals + Memory system for learned details. All local.

### 3. ADAPTIVE TONE ENGINE (Write Like You, Per Person)

**What**: Eidos learns how you write to different people and drafts messages in YOUR voice.

**Features**:
- Knows you text Mom with emojis and short sentences
- Knows you email your boss formally with structured bullet points
- Knows you're casual with college friends, use specific slang
- Per-recipient tone profiles stored in memory

**Why nobody does this**: Spark and WriteMail.ai do generic "style matching" but cloud-based and not per-recipient. Nobody does per-person tone adaptation on-device.

**iOS implementation**: Analyze user's message drafts (from share extension input or manual samples) → extract tone features per contact → store in people.md memory → apply when drafting.

### 4. PASSIVE LIFE LOGGING WITH PATTERN RECOGNITION

**What**: Eidos automatically captures the shape of your day and surfaces insights without manual journaling.

**Features**:
- Auto-log from device signals: Calendar events attended, contacts communicated with, locations visited (with permission), health metrics (sleep, steps, HRV)
- Weekly insight: "You slept 20% better on weeks you exercised 3+ times"
- Mood correlation: "Your productivity peaks on Tuesdays — you had 3 deep work blocks"
- Behavioral drift detection: "You've been skipping your morning routine for 5 days"
- Memory integration: important moments auto-tagged with higher priority

**Why nobody does this**: Journaling apps (Daylio, Rosebud) require manual input. Quantified self apps show data but no AI insights. Nobody combines passive capture + AI pattern recognition on-device.

**iOS implementation**: HealthKit + EventKit + Location + Memory system. Nightly crystallization extracts patterns during charging.

### 5. CONTEXT-STITCHING ACROSS DATA SOURCES

**What**: Eidos connects dots across your calendar, messages, notes, and memory that no single app can.

**Example queries**:
- "What did I tell Sarah about the Tokyo trip?" → searches memory + contacts + calendar
- "Prepare me for my meeting with Alex" → pulls calendar event + last conversation summary + relationship notes + relevant KB entries
- "What's going on this week?" → unified view across all data sources, not just calendar

**Why nobody does this**: Each app is siloed. Siri promised "Personal Context" but delayed. No third-party app stitches calendar + messages + notes + relationships + health into a unified context.

**iOS implementation**: Already architected — KnowledgeRepository + hybrid RRF search + memory system. Just needs more data sources feeding in.

### 6. SMART ROUTINE LEARNING AND ADAPTATION

**What**: Eidos learns your daily patterns and adapts to changes.

**Features**:
- Learns: "User orders Uber at 8:15am weekdays to Financial District"
- Adapts: "Today you have a 9am at a different location. Adjusting ride suggestion."
- Learns: "User calls Mom every Sunday evening"
- Nudges: "It's Sunday 6pm — want to call Mom?"
- Learns: "User reviews email at 8am, works deep 10am-12pm, meetings 2-4pm"
- Protects: "You have a meeting request at 10:30am — this conflicts with your deep work block."

**Why nobody does this**: Calendar apps show what's scheduled but don't learn habits. No app detects routine patterns and proactively adapts.

**iOS implementation**: Memory system stores routines.md with learned patterns. BGProcessingTask analyzes past week's signals nightly.

---

## Master Phase Plan

### Phase 0 — Scaffolding: COMPLETE
66 files, all compiling, XcodeGen project, SwiftData, entitlements, stubs.

### Phase 1 — Persistence + Embeddings: COMPLETE
EmbeddingService, VectorStore, KnowledgeRepository, TextChunker, hybrid RRF search, content-hash dedup, 5 test files.

### Phase 2 — Inference Bring-Up: COMPLETE (pending real-device validation)
MLX Swift, GemmaSession, ModelDownloader, HuggingFaceDownloader (URLSession-based, bypasses the stalling swift-huggingface client), EgressGuard with host-suffix allowlist, PromptTemplates, onboarding UI, streaming chat.
**Milestone achieved**: User types prompt → Gemma 4 E2B streams response on-device. Validated on Mac (Designed for iPad) with local inference + 1.5 GB HF download path.

**2d — Real-device TODO** (when an iPhone 13+ is available):
- [ ] Plug in iPhone, sign into Xcode with same Personal Team
- [ ] Select device, ⌘R, accept developer cert on iPhone (Settings → VPN & Device Management)
- [ ] Onboarding downloads model over the real phone's connection
- [ ] Toggle Airplane Mode → confirm inference still works (zero egress)
- [ ] Measure: tokens/sec, RAM peak, thermal state under 30 s generation

### Phase 3 — Memory System + RAG Chat: COMPLETE (85 tests passing)
All sub-phases shipped: MemoryManager / MemoryIndex / MemoryDecayEngine / MemoryCrystallizer, ContextBuilder, RAGPipeline, ChatViewModel rewired through pipeline + crystallization-on-session-end, SpeechTranscriber (on-device SFSpeechRecognizer), full KB browser with search/edit/delete. Permission strings baked into project.yml.

### Phase 3 — DETAILS (historical):

**Goal**: Eidos remembers everything across sessions and retrieves relevant context per query.

**3.1 — Memory File Manager**
- `MemoryManager.swift` — reads/writes/updates MD memory files
- `MemoryIndex.swift` — maintains _index.md, topic file registry
- `MemoryCrystallizer.swift` — end-of-session summarization pipeline
- `MemoryDecayEngine.swift` — priority scoring, retention calculation, eviction
- File structure: core_identity, calendar_upcoming, active_priorities, recent_sessions, topic files, conversations/, archive/

**3.2 — Memory-Aware RAG Pipeline**
- `RAGPipeline.swift` — single-pass chat with Gemma 4 function calling (A2)
- `ContextBuilder.swift` — assembles memory context + KB results into prompt (~7K token budget)
- Memory injection: always-loaded core files + index-selected topic files + RAG fallback
- Token budget enforcement: hard cap at ~7K memory tokens to stay in small model sweet spot

**3.3 — Chat with Memory**
- `ChatViewModel.send()` — full pipeline: memory load → RAG retrieve → Gemma generate → memory update
- Incremental persistence during streaming (B10)
- End-of-conversation crystallization trigger
- `StreamingText.swift` — token-by-token display

**3.4 — Voice Input**
- `SpeechTranscriber.swift` — WhisperKit integration for on-device STT
- `ChatInputBar.swift` — mic button, push-to-talk or auto-detect silence
- Real-time transcription → feed to chat pipeline

**3.5 — Knowledge Base UI**
- `KBBrowserView.swift` — browse stored knowledge entries
- `KBEntryDetailView.swift` — view/edit individual entries

**Milestone**: "What did I tell you about X last week?" returns the correct answer from memory. Conversations persist and crystallize across sessions.

### Phase 4 — Platform Sources + Skills + Home UI: COMPLETE (95 tests)
4.1 CalendarSource (events+reminders read/write) + ContactsSource (search) shipped. 4.2 Real implementations of CalendarSkill, RemindersSkill, CreateReminderSkill, ContactsSkill, SearchKBSkill, AddNoteSkill, DigestSkill — all wired into SkillRegistry. 4.5 DigestGenerator (calendar + reminders + memory → Gemma → briefing), HomeView + HomeViewModel with streaming digest card. 10 new SkillsTests. Permission strings for calendar/contacts/reminders/mic/speech baked into project.yml.

**Explicitly deferred** (each a dedicated session's worth of work):
- **4.3 Relationship Intelligence** — RelationshipTracker, health scoring, pre-meeting briefings. Needs careful privacy design + communication-signal extraction from Messages/Mail (neither is directly readable on iOS — requires Share-Extension ingestion first, pushing toward Phase 5).
- **4.4 Smart Notifications** — ProactiveEngine + notification budget. Needs UNUserNotificationCenter permission flow, background task support, and a clear retention policy for what generates a notification vs. what doesn't.

### Phase 4 — DETAILS (historical):

**Goal**: Eidos reads and writes your calendar, contacts, reminders and builds relationship intelligence.

**4.1 — Platform Sources**
- `CalendarSource.swift` — EventKit: fetch events, create events, find free slots
- `ContactsSource.swift` — CNContacts: full CRUD, relationship data, communication signals (B2 fix)
- `RemindersSource.swift` — EventKit: fetch/create/complete reminders

**4.2 — Skill Implementations**
- `SearchKBSkill.swift` — search knowledge base via function calling
- `AddNoteSkill.swift` — add to knowledge base
- `CalendarSkill.swift` — create/query/modify calendar events via natural language
- `RemindersSkill.swift` — create/query/complete reminders
- `ContactsSkill.swift` — lookup/add/update contacts
- `DigestSkill.swift` — generate daily briefing on demand

**4.3 — Relationship Intelligence** (NEW)
- `RelationshipTracker.swift` — analyze communication patterns per contact
- `RelationshipMemory.swift` — auto-populate people.md with learned details
- Relationship health scoring: frequency trend, last interaction, important dates
- Pre-meeting briefing: pull relationship context + last conversation topics
- Nudges: "Haven't talked to X in Y days" via notification

**4.4 — Smart Notifications** (NEW)
- `ProactiveEngine.swift` — generates contextual nudges from memory + calendar + contacts
- Notification scheduling: follow-up reminders, relationship nudges, routine prompts
- Respects notification budget (64 pending limit) with priority ranking

**4.5 — Home + Digest**
- `HomeView.swift` — tab bar root with digest card, quick actions, upcoming events
- `HomeViewModel.swift` — assembles daily briefing data
- `DigestGenerator.swift` — morning briefing: calendar + reminders + relationship nudges + weather + health + memory highlights

**Milestone**: "What's on my calendar this week?" → correct answer. "Remind me to call Sarah" → reminder created. "Prepare me for my meeting with Alex" → relationship context + calendar + memory.

### Phase 5 — App Actions + Ingestion: COMPLETE (113 tests, 5.2 share ext. deferred, 5.4 Shortcuts deferred)

**5.1 URL action layer** shipped: `AppAction` enum (WhatsApp/SMS/Email/Call/Maps/Uber/FaceTime), `AppActionRegistry` actor-lite (MainActor @Observable), 6 new skills (SendWhatsApp/SMS/Email, PlaceCall, Navigate, RequestRide), `ActionConfirmationSheet` UI with masked phone numbers + "you tap Send in the target app" disclaimer. `LSApplicationQueriesSchemes` baked into project.yml.

**5.3 Data importers** shipped: `WhatsAppImporter` (multi-locale regex, continuation lines, stripInvisibles for LTR/RTL marks, B12 done), `MailImporter` (mbox split, header parse, quoted-printable + base64 decode, UIKit-gated HTML→text, B13 done), `PlainTextImporter` (simple insert), `IngestionCoordinator` (App-Group queue drain + direct-import API, retries failures).

**Explicitly deferred**:
- **5.2 Share Extension real impl** — App Group `group.com.eidos.shared` needs entitlements on both targets and a paid Apple ID to register the group. Current `ShareViewController` is a scaffold. Until then, direct imports from the main app (`IngestView`) use the same importer paths.
- **5.4 Shortcuts / App Intents** — separate session. Requires `AppIntent` conformance for each skill and Spotlight registration.

### Phase 5 — DETAILS (historical):

**Goal**: Eidos reaches out to other apps and ingests external data.

**5.1 — URL Scheme Action Layer** (NEW)
- `AppActionRegistry.swift` — registry of known URL schemes and their parameter formats
- `AppActionBuilder.swift` — construct URL scheme calls from natural language
- Supported actions:
  - WhatsApp: `whatsapp://send?phone=X&text=Y` (pre-fill, user confirms)
  - SMS: `sms:X&body=Y`
  - Email: `mailto:X?subject=Y&body=Z`
  - Phone: `tel:X`
  - Maps: `maps://?daddr=X&dirflg=d`
  - Uber: `uber://?action=setPickup&dropoff[latitude]=X`
  - Google Maps: `comgooglemaps://?daddr=X`
  - FaceTime: `facetime://X`
- Confirmation flow: Eidos shows what it will do → user approves → URL scheme fires
- `canOpenURL()` checks with LSApplicationQueriesSchemes in Info.plist

**5.2 — Share Extension**
- `ShareViewController.swift` — accept text, URLs, files, images from any app
- App Group queue: save to `group.com.eidos.shared` container
- `.completeFileProtection` on shared files (B6)

**5.3 — Data Importers**
- `IngestionCoordinator.swift` — process App Group queue (B3 regex fix)
- `WhatsAppImporter.swift` — multi-locale regex parser (B12)
- `MailImporter.swift` — real MIME + HTML→text (B13)
- `PlainTextImporter.swift` — .txt, .md file import
- Content-hash dedup shown in results (B8)
- `IngestView.swift` — import status UI

**5.4 — Shortcuts Integration** (NEW)
- Ship pre-built .shortcut files for common workflows
- Example: "Morning routine" shortcut: Eidos digest → Weather → Calendar → News
- App Intents: expose key Eidos actions to Siri and Shortcuts
- `EidosShortcutsProvider.swift` — register App Shortcuts for Spotlight/Siri

**Milestone**: "Text Sarah that I'll be 10 min late" → WhatsApp opens with message pre-filled. Share a webpage → Eidos ingests and indexes it. "What was in that article about X?" → answer from ingested content.

### Phase 6 — Proactive Intelligence + Routines: COMPLETE (120 tests, 6.1/6.4/6.5 deferred)

**6.2 Proactive digest** shipped: `ProactiveDigestGenerator` with structured `ProactiveSignals` (events, reminders, memory highlights, health insight, nudges) and Gemma narration. `HomeViewModel` + `HomeView` rewired to use it — shows a nudges card when stale `active_priorities` memories exist.

**6.3 HealthKit** shipped: `HealthSource` actor reading sleep / steps / resting HR / active energy for the last 24h. Permissions requested via `HKHealthStore.requestAuthorization`. `NSHealthShareUsageDescription` + `NSHealthUpdateUsageDescription` + `com.apple.developer.healthkit` entitlement all baked into project.yml. `HealthInsight` struct has a one-line `readableLine` for prompt injection.

**6.x Notifications** shipped: `NotificationScheduler` with `UNUserNotificationCenter` permission flow, `scheduleMorningDigest()` (daily repeating `UNCalendarNotificationTrigger` at configurable hour/minute), `scheduleNudge(id:title:body:fireAt:)` with 20-item budget (Apple caps pending at 64 — we leave 44 headroom for other sources). SettingsView exposes the toggle + time picker + health permission button.

**Explicitly deferred**:
- **6.1 RoutineLearner** — pattern detection over calendar/location/health history requires months of usage data. The signal-gathering infrastructure is ready; the stats pass can ship after real-world logging accrues.
- **6.4 LifeLogEngine** — passive day-shape logging + nightly crystallization is a dedicated session. `MemoryCrystallizer` already handles per-session; extending to scheduled background passes needs BackgroundTasks registration.
- **6.5 Tone Engine** — needs Share-Extension ingestion of real user messages first. Deferred with 5.2.

### Phase 6 — DETAILS (historical):

**Goal**: Eidos stops being reactive and starts thinking ahead.

**6.1 — Routine Learning Engine** (NEW)
- `RoutineLearner.swift` — analyze calendar + location + health patterns
- Detect daily/weekly patterns: commute times, deep work blocks, call habits
- Store in routines.md with confidence scores
- Adapt suggestions when routine breaks: different location, sick day, holiday

**6.2 — Proactive Digest** (NEW)
- `ProactiveDigestGenerator.swift` — enhanced morning briefing
  - Calendar events + travel time estimates
  - Relationship nudges ("Mom's birthday tomorrow")
  - Follow-up reminders ("You told Alex you'd review the doc")
  - Health insights ("You slept 6.2h, below your 7.5h average")
  - Routine deviations ("No gym scheduled today, usually you go Tuesdays")
  - Weather for outdoor events
- Widget timeline: pre-computed insights for home/lock screen
- Live Activity for time-sensitive items (upcoming meeting, ride departure)

**6.3 — HealthKit Integration** (NEW)
- `HealthSource.swift` — read sleep, steps, HRV, workouts, active energy
- Pattern detection: sleep vs productivity, exercise vs mood, behavioral trends
- Health insights stored in health.md memory
- Privacy: HealthKit data never leaves device, never stored raw — only insights

**6.4 — Passive Life Logging** (NEW)
- `LifeLogEngine.swift` — auto-capture day shape from device signals
- Signals: calendar events attended, contacts communicated with, locations, health metrics
- Nightly crystallization: day summary → weekly summary → monthly patterns
- Queryable: "What did I do last Tuesday?" → reconstructed from logs

**6.5 — Tone Engine** (NEW)
- `ToneProfile.swift` — per-contact writing style profile
- Learn from user's shared message samples (via share extension)
- Profiles: formality level, emoji usage, sentence length, greeting/sign-off patterns, specific slang
- Apply when drafting messages for specific recipients

**Milestone**: Eidos sends morning notification with digest. Widget shows next action. "Prepare a ride for my usual commute" → Uber URL with learned destination. Weekly insight: "You were most productive on days you slept 7+ hours."

### Phase 7 — Polish + Ship: COMPLETE (123 tests, 0 failures)

**7.1 Conversation persistence** — `ChatViewModel` rewired to SwiftData `Conversation`/`ConversationMessage`. Auto-resumes the most recent conversation on launch. New `+` button in the chat toolbar starts a fresh one. Old conversations live in storage (browser UI deferred).

**7.2 Memory browser** — new Memory tab (`MemoryBrowserView` + `MemoryEntryDetailView`). Lists every memory grouped by tier, searchable, with priority badges. Detail view edits body/priority/tier, supports delete, "mark as hot" (touch), and export. Trust-feature: user can audit every claim the "remembers everything" system makes.

**7.3 Smarter crystallization** — `ChatViewModel.endSession()` now guards by `turnsSinceCrystallize >= 3` AND `>60s since last crystallize`. Tab switches no longer burn Gemma cycles on trivial conversations.

**7.4 Friendly error messages** — `UserFacingError` maps `GemmaError`, `MemoryManagerError`, `MemoryCrystallizerError`, `HuggingFaceError`, `CalendarError`, plus common NSURLErrorDomain / POSIX codes to readable strings. `ChatViewModel.errorMessage` routed through it.

**7.5 Memory export** — `MemoryExporter.exportAsZip(manager:)` writes every `MemoryEntry` back out to MD files under a timestamped tmp dir. `share(_:)` hands the URL to `UIActivityViewController` — user can save to Files, AirDrop, mail. Accessible from MemoryBrowserView's overflow menu.

**7.6 Feature tour** — `FeatureTourView` with 3 slides (voice, morning briefing, app actions with confirmation). Shown once after first model download. Dismissable. State in UserDefaults.

**7.9 Integration test** — `RAGIntegrationTests` exercises real `ContextBuilder` + `MemoryManager` + in-memory `KnowledgeRepository`. Catches API drift between the pieces that matter at runtime.

**7.10 README + KNOWN_LIMITATIONS.md** — honest inventory. Every deferred item has a clear reason. Environmental gotchas (Metal Toolchain, macro trust, simulator MLX) documented.

### Phase 7 — DETAILS (historical):

**Goal**: Production-ready iOS app.

**7.1 — Settings**
- `SettingsView.swift` — model swap (E2B ↔ E4B), clear KB, memory management, EgressGuard status, notification preferences, privacy dashboard

**7.2 — UI Polish**
- Launch screen, app icon, haptics, animations
- Dark mode, Dynamic Type, accessibility
- Onboarding refinement with privacy-first messaging

**7.3 — Testing**
- Full EidosTests suite (B15)
- Memory system tests: decay, crystallization, index selection
- Skill tests: calendar CRUD, contact lookup, reminder creation
- EgressGuard: zero-egress verification
- Integration tests: share extension → ingest → search → find

**7.4 — Performance**
- Memory budget enforcement: cap total memory tokens
- Thermal guards (B11): throttle on .serious, halt on .critical
- Background task optimization: crystallization during charging only
- Model warmup optimization: <20s cold start target

**7.5 — App Intents + Spotlight** (NEW)
- Register all skills as App Intents for Siri
- Index knowledge base entries in Spotlight via CSSearchableItem
- Focus Filter support: adapt behavior per Focus mode

**Milestone**: Ship to TestFlight. All tests green. Airplane mode works. Privacy promise verifiable.

---

## Architecture Overview (Updated)

```
┌─────────────────────────────────────────────────┐
│                    EidosApp                       │
│               (SwiftUI @main)                    │
├──────────────┬──────────────┬────────────────────┤
│   ChatView   │  HomeView    │   SettingsView     │
│   KBBrowser  │  DigestCard  │   MemoryManager    │
│   IngestView │  Widget      │   PrivacyDashboard │
├──────────────┴──────────────┴────────────────────┤
│              AppContainer (DI)                    │
├──────────────────────────────────────────────────┤
│                RAG Pipeline                       │
│  Memory Load → Context Build → Gemma Generate    │
│  → Skill Dispatch → Memory Update                │
├─────────┬────────────┬───────────┬───────────────┤
│ Memory  │ Knowledge  │ Inference │  Platform      │
│ System  │ Base       │           │  Sources       │
│         │            │           │                │
│ Index   │ SwiftData  │ MLX Swift │  EventKit      │
│ MD Files│ VectorStore│ Gemma 4   │  CNContacts    │
│ Decay   │ Embeddings │ WhisperKit│  HealthKit     │
│ Crystal │ sqlite-vec │ Streaming │  URL Schemes   │
├─────────┴────────────┴───────────┴───────────────┤
│              Proactive Engine                     │
│  Routine Learning → Digest → Notifications       │
│  Relationship Tracking → Nudges → Widgets        │
├──────────────────────────────────────────────────┤
│              EgressGuard (URLProtocol)            │
│  Zero egress after onboarding — enforced by code │
└──────────────────────────────────────────────────┘
```

---

## What Makes Eidos Different

| Competitor | What They Do | What Eidos Does Better |
|-----------|-------------|----------------------|
| **Siri** | Reactive, cloud-dependent, can't remember, delayed 2+ years | Proactive, on-device, persistent memory, shipping now |
| **ChatGPT app** | Smart but cloud-only, no device integration, no memory across sessions | Local, integrates with calendar/contacts/health, persistent memory |
| **Rabbit R1** | Tried universal app control, failed (7% success) | Focused scope that works: EventKit + URL schemes + memory |
| **Google Gemini** | Good in Google ecosystem only, cloud-dependent | Cross-app context stitching, works offline, privacy-first |
| **Personal CRMs** (Clay, Monica) | Manual data entry, web-based, transactional feel | Passive relationship learning, on-device, feels natural |
| **Journaling apps** (Daylio, Rosebud) | Require manual input, no AI pattern recognition | Passive life logging, auto-capture, AI insights |
| **Morning briefing apps** (DayStart) | Single-channel (just news or just calendar) | Unified: calendar + relationships + health + memory + tasks |

---

## The Privacy Moat

This is Eidos's deepest competitive advantage:

1. **EgressGuard** — URLProtocol blocks ALL network after model download. Not a promise — a code-enforced guarantee.
2. **No telemetry, no analytics, no crash reporting** — nothing phones home, ever.
3. **`.completeFileProtection`** — database unreadable when device is locked.
4. **On-device inference** — Gemma 4 runs locally, no API calls.
5. **On-device embeddings** — Apple NLContextualEmbedding, no cloud.
6. **Verifiable** — users can inspect EgressGuard logs to see zero outbound requests.

In a world where 71% of consumers worry about AI data collection and 44% have avoided AI tools for privacy reasons, this is a $3.4B+ market opportunity.

---

## Timeline Priority (What to Build First)

```
NOW:        Phase 2 (Inference) — Get Gemma talking on iPhone
THEN:       Phase 3 (Memory + RAG) — The core differentiator  
THEN:       Phase 4 (Skills + Relationships) — Make it useful
THEN:       Phase 5 (App Actions + Ingestion) — Reach into other apps
THEN:       Phase 6 (Proactive Intelligence) — The wow factor
FINALLY:    Phase 7 (Polish + Ship) — TestFlight ready
```

Each phase is shippable independently. Phase 3 alone (memory + chat) is a useful product. Each subsequent phase adds a layer of capability.
