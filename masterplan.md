# Eidos — Master Plan (v3)

**Last updated**: 2026-04-26
**Vision**: The on-device multimodal AI that does what Siri can't — sees, hears, remembers everything, acts on your behalf, and never leaks your data.

> **Source of truth.** Every design decision, feature request, and phase plan gets reconciled against this file. Code changes that introduce new architecture update this doc in the same commit. If CLAUDE.md and this file conflict, this file wins.

---

## What We're Building

An on-device iOS AI personal assistant that:
1. **Remembers** — persistent context across all conversations with priority-based memory
2. **Acts** — controls calendar, reminders, contacts, and hands off to apps via URL schemes
3. **Knows you** — learns your relationships, routines, tone, and preferences
4. **Sees and hears** — Gemma 4 multimodal stack with native text + image today, plus fully-local voice input and a native-audio bridge ready for the first `mlx-swift-lm` release that exposes raw audio attachments
5. **Is a staff of specialists** — master persona + on-device skills (fitness, nutrition, wellness, programmer, tutor)
6. **Stays private** — zero data egress after setup, enforced by code (EgressGuard)
7. **Is proactive** — surfaces what you need before you ask (morning digest, relationship nudges)
8. **Is observable** — full developer diagnostics: logs, metrics, benchmarks, failure taxonomy
9. **Fades into the phone** — prepares, suggests, and quietly acts with permission so the best interaction is often no interaction

---

## Current State — 2026-04-26

| Area | Status |
|---|---|
| Scaffolding (Phase 0) | ✅ complete |
| Persistence + embeddings (Phase 1) | ✅ complete |
| Inference bring-up (Phase 2) | ✅ complete — simulator uses mocked path, Mac (Designed for iPad) runs real Gemma 4 E2B |
| Memory + RAG (Phase 3) | ✅ complete |
| Skills + Home (Phase 4) | ✅ complete (14 skills wired), relationship intel and tone engine deferred |
| App actions + ingestion (Phase 5) | ✅ complete, Share Ext implemented (pending App Group provisioning on real device) |
| Proactive + HealthKit (Phase 6) | ✅ complete (6.1 RoutineLearner, 6.4 LifeLogEngine, 6.5 Tone Engine deferred) |
| Polish + ship (Phase 7) | ✅ complete |
| **Widgets + Live Activities + Control Widgets (iOS 18+)** | ✅ shipped |
| **23 App Intents + 10 Siri phrases + Shortcuts recipes** | ✅ shipped |
| **Ambient data sources (Location, Motion, Music, Focus)** | ✅ shipped |
| **UILaunchScreen / full-screen layout fix** | ✅ shipped |
| **Simulator mock path (Gemma + Speech + Download)** | ✅ shipped |
| **Phase 8 — Multimodal + Observability** | ✅ complete — observability, safety, MLXVLM image path, benchmark fixtures, Markdown response rendering, model-load tester guardrails, startup model verification, force-fresh AltStore tester reset, and 193 green tests shipped; native raw-audio-to-Gemma explicitly blocked by current MLX API surface |
| **Phase 9 — Skills / Personas** | ▶️ next — design locked, implementation after Phase 8 |

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
| Voice input | Apple's on-device speech recognition today, with raw PCM capture path ready for the native-audio bridge | P1 |
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

### Android port — deferred, in scope for post-iOS-ship

User intent (2026-04-24): once iOS Eidos works out, ship an Android version that **aligns with the full vision without iOS's sandbox restrictions** — DeviceActivityMonitor limits, Widget-requires-App-Group, App Store fees. Android's AccessibilityService + Foreground Service + broader permission model unblocks everything iOS denies. See table below for what Android recovers.

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

## Product Laws For Ambient Eidos

These rules govern every future feature if the goal is for Eidos to feel like
another part of the phone instead of a chatbot living inside an app.

1. **Situation solved > chat turn completed.** The success metric is fewer
   commands over time, not more messages per day.
2. **Prepare more than you execute.** Eidos should precompute drafts, routes,
   briefs, reminder suggestions, and follow-ups before it interrupts or acts.
3. **Authority is earned, never assumed.** Every domain climbs a ladder:
   `observe -> suggest -> draft -> confirm -> auto_act`.
4. **Every action needs a receipt.** If Eidos did something, the user should
   be able to inspect why, what data informed it, and how to undo it.
5. **Background work must be event-driven and battery-safe.** Build around
   calendar changes, significant location, motion transitions, charging
   windows, widgets, and notifications — not a fantasy continuous agent that
   iOS will kill.
6. **Keep the human-audit layer.** Markdown memory stays because it is a trust
   feature, but autonomy-critical state must also live in structured stores
   where reasoning and actions are reliable.

---

## Master Phase Plan

### Phase 0 — Scaffolding: COMPLETE
66 files, all compiling, XcodeGen project, SwiftData, entitlements, stubs.

### Phase 1 — Persistence + Embeddings: COMPLETE
EmbeddingService, VectorStore, KnowledgeRepository, TextChunker, hybrid RRF search, content-hash dedup, 5 test files.

### Phase 2 — Inference Bring-Up: COMPLETE (pending real-device validation)
MLX Swift, GemmaSession, ModelDownloader, HuggingFaceDownloader (URLSession-based, bypasses the stalling swift-huggingface client), EgressGuard with host-suffix allowlist, PromptTemplates, onboarding UI, streaming chat.
**Milestone achieved**: User types prompt → Gemma 4 E2B streams response on-device. Validated on Mac (Designed for iPad) with local inference + 1.5 GB HF download path.

**2d — Real-device TODO** (when an iPhone 15 Pro+ / iOS 26 device is available):
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
- `SpeechTranscriber.swift` — Apple's on-device STT (shipping path)
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

### Phase 5 — App Actions + Ingestion: COMPLETE (share ext + App Intents shipped)

**5.1 URL action layer** shipped: `AppAction` enum (WhatsApp/SMS/Email/Call/Maps/Uber/FaceTime), `AppActionRegistry` actor-lite (MainActor @Observable), 6 new skills (SendWhatsApp/SMS/Email, PlaceCall, Navigate, RequestRide), `ActionConfirmationSheet` UI with masked phone numbers + "you tap Send in the target app" disclaimer. `LSApplicationQueriesSchemes` baked into project.yml.

**5.3 Data importers** shipped: `WhatsAppImporter` (multi-locale regex, continuation lines, stripInvisibles for LTR/RTL marks, B12 done), `MailImporter` (mbox split, header parse, quoted-printable + base64 decode, UIKit-gated HTML→text, B13 done), `PlainTextImporter` (simple insert), `IngestionCoordinator` (App-Group queue drain + direct-import API, retries failures).

**Later updates**:
- **5.2 Share Extension real impl** — shipped. `ShareViewController` writes shared items into the App Group queue; paid Apple Developer provisioning is still the clean path for App Group registration.
- **5.4 Shortcuts / App Intents** — shipped. Eidos exposes 23 App Intents and 10 Siri phrases; see `SHORTCUTS.md`.

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
- App Group queue: save to `group.com.hissamuddin.eidos` container
- `.completeFileProtection` on shared files (B6)
- Current App Group identifier in code: `group.com.hissamuddin.eidos`

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

**7.10 README + KNOWN_LIMITATIONS.md** — honest inventory. Every deferred item has a clear reason. Environmental gotchas (Metal Toolchain, macro trust, simulator MLX, AltStore/free-team entitlement friction) documented.

### Phase 7 — DETAILS (historical):

**Goal**: Production-ready iOS app.

**7.1 — Settings**
- `SettingsView.swift` — model swap infrastructure, clear KB, memory management, EgressGuard status, notification preferences, privacy dashboard; Release tester builds expose E2B only until real-device loading is validated

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

### Phase 8 — Multimodal + Observability: COMPLETE (2026-04-25)

**Goal**: Ship Gemma 4's practical on-device multimodal capability plus developer-grade diagnostics so we can measure, benchmark, and harden the product. Text + image are native end-to-end. Voice input stays fully local, and the raw-audio-to-Gemma bridge is now explicitly gated on upstream `mlx-swift-lm` API support rather than vague repo debt.

**Trigger**: Gemma 4 released 2026-04-02 with native multimodality. Our current `MLXLLM` pipeline is text-only — we must upgrade to `MLXVLM` to unlock vision and audio. Simultaneously this is our first time stress-testing the product, so observability must land at the same time.

#### Progress (2026-04-25)

✅ **Shipped in this session**:
- `EidosFeatureFlags` — runtime toggles for vision / audio / reasoning / personas / diagnostics / long-context / safety-gate
- `FailureCategory` — 25-case typed failure taxonomy
- `EidosLogger` — JSONL logger with categories, levels, listener, export, unified-log mirror
- `MetricsRecorder` — per-generation TTFT, tok/s, RSS (via `mach_task_basic_info`), thermal sampling
- `SafetyGate` — pre-LLM hardcoded refusal for self-harm / medical emergency / dosing / diagnosis / legal / child-safety; curated responses with real emergency numbers (988, 911, 112, Childhelp, Poison Control)
- `ReasoningMode` — chain-of-thought system-prompt prefix, `.fast` / `.reasoning`
- `AudioCaptureService` — 16 kHz mono Int16 PCM, in-memory, VAD auto-stop, simulator mock
- `VisionCaptureService` — camera availability, PhotosPicker decoding, CGImage return
- `BenchmarkCorpus` — 11-category corpus with 20+ prompts and per-prompt rubrics
- `BenchmarkRunner` — sequential executor, per-prompt metrics, JSON report persistence, safety-gate aware
- `DiagnosticsView` — in-app Logs / Metrics / Benchmarks / Flags panes (wired into Settings)
- `AppContainer` exposes `benchmarkRunner`, `audioCaptureService`, `visionCaptureService`
- `GemmaSession.generate(messages:images:audio:reasoning:)` — unified multimodal entry point backed by `MLXVLM` for image input; raw audio remains feature-gated because the current `mlx-swift-lm` public `UserInput` / `Chat.Message` API still lacks audio attachments
- Unit tests: `SafetyGateTests`, `EidosLoggerTests`, `BenchmarkRunnerTests`, `AudioCaptureServiceTests`, `GemmaSessionMultimodalTests`, plus prompt/parser regression coverage
- `project.yml` — `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` added
- `EidosApp` — gate observes `phase` so download→RootView transition fires automatically and never opens chat before MLX reports `.ready`
- `ModelDownloadView` — explicit "Start using Eidos" continue button on ready state
- `ChatInputBar` / `ChatViewModel` / `RAGPipeline` — image attachments and future-ready audio attachments plumbed end-to-end through the chat stack
- `BenchmarkRunner` — synthetic vision fixtures plus concrete OCR / scene rubrics, so the benchmark suite now actually exercises image prompts
- `LocationSource` — reverse geocoding migrated to `MKReverseGeocodingRequest`, restoring the zero-warning bar for this path
- `EidosTests` — **192 / 192 green** on iPhone 17 simulator; signed `generic/platform=iOS` build succeeds

✅ **Phase-8 exit status (2026-04-25)**:
- **8.4c MLXVLM swap** — complete for image input. `GemmaSession.generateMultimodal(...)` now runs the `MLXVLM` path and chat/benchmark callers feed it real `CGImage` attachments.
- **8.6b Vision in chat** — complete. Camera / photo picker attachments flow through `ChatInputBar` → `ChatViewModel` → `RAGPipeline` → `GemmaSession`.
- **8.9b Benchmark rubrics + tests** — complete for repo scope. Vision prompts now use bundled synthetic fixtures with concrete rubrics, and missing Phase 8 tests landed (`BenchmarkRunnerTests`, `AudioCaptureServiceTests`, `GemmaSessionMultimodalTests`).
- **Native raw audio → Gemma** — no longer treated as vague unfinished repo work. The current `mlx-swift-lm` public surface exposes images/videos but not raw audio attachments, so `GemmaSession.supportsNativeAudioInput` is explicitly `false`. Shipping voice input remains fully local via `SpeechTranscriber`; the `AudioCaptureService` + chat plumbing stay ready for the first upstream release that exposes the attachment API.

✅ **Critical fix shipped 2026-04-23 (Phase 8 batch 3 — "The Brain Fix")**:

**Discovery**: investigating why Gemma couldn't set reminders or take actions, we found the skill pipeline was completely disconnected. `SkillParser.parse()`, `SkillRegistry.dispatch()`, and the `toolSchemasJSON` parameter of `PromptTemplates.chat()` were never called anywhere in the app. Gemma produced text about reminders but nothing ever executed.

**Fixed**:
- `RAGPipeline.chat()` now **builds a tool catalogue** from `SkillRegistry.enabledSkills` and injects it via `toolSchemasJSON`.
- `RAGPipeline.runWithToolLoop()` — buffers the first 48 chars of Gemma's reply, detects JSON tool-call syntax, parses via `SkillParser`, dispatches via `SkillRegistry`, and re-prompts Gemma with the tool result so the final user-visible reply is a natural-language confirmation ("Reminder created: Call mom at 6 pm").
- `RAGPipeline.hasBalancedBraces()` — lightweight tool-call completeness detector so we know when the full JSON has arrived without a full JSON parser in the hot path.
- `PromptTemplates.systemPrompt` — **new "Using tools" section** instructs Gemma when to emit a tool call vs prose, and explicitly notes that iOS alarms are impossible (route to reminders instead) and messages can only be pre-filled.
- `RAGPipelineToolLoopTests` — regression tests for brace balance + parser robustness to prose / markdown wrapping / missing keys.

**What changes for the user**: "Remind me to call mom at 6 pm" now **actually creates a reminder in the iOS Reminders app**. "What's on my calendar tomorrow?" fetches real events. "Text John I'll be late" opens Messages pre-filled. Everything that `SkillRegistry` has a skill for now works end-to-end.

✅ **Additional work shipped 2026-04-23 (Phase 8 batch 2)**:
- `PromptTemplates.runtimeContextBlock()` — inject current date / time / timezone / locale / user name. Fixes the "Eidos can't answer 'what day is it?'" bug.
- `PromptTemplates.systemPrompt` rewritten with 12 behavior rules (use runtime block, use memory, don't fabricate, defer clinical topics, match user's language, admit smallness).
- `RAGPipeline.chat()` — `SafetyGate.evaluate()` runs pre-Gemma; refusal streams a hardcoded response without touching the LLM.
- `MemoryCrystallizer.crystallize()` — gained SafetyGate guard + mem0-style **ADD / UPDATE / DELETE / NONE** reconciliation pass against existing memories, eliminating the "same fact stored five times" bug.
- `PromptTemplates.reconciliationSystemPrompt` — new prompt for the crystallizer's reconciliation turn.
- `MemoryIndex.search(titleSubstring:)` — supports reconciliation's candidate lookup.
- `ContextBuilder` — long-context packing (60 K chars / 15 K tokens when `longContextPackingEnabled`) with topic cap 30 and KB topK 10.
- `DiagnosticsView` → Chats tab — browse every persisted `Conversation` + transcript export as markdown. Resolves "conversation history has no browser" from `KNOWN_LIMITATIONS.md`.
- `SettingsView` → Model switcher — swap infrastructure with download + reload flow (`ModelSwitcherView.swift`); E4B is DEBUG/dev-only until E2B passes real-device loading.
- `ChatInputBar` — image attachments now flow end-to-end through chat, and audio attachments are stored/plumbed future-ready while `SpeechTranscriber` remains the default shipping voice path.
- Tests: `PromptTemplatesRuntimeTests` for the runtime-context block ordering and content.

#### 8.1 — Engineering bar for everything in Phase 8+

Non-negotiable commitments for every line of code in this phase and beyond:

1. **Every public API has `///` doc comments.** Contributors can read any file without asking.
2. **Every error path is a typed error.** No raw `NSError`. Every throw site carries `errorDescription` suitable for UI.
3. **Swift 6 strict concurrency, zero warnings.** All shared state is actor-isolated, `Sendable`, or explicitly `@unchecked Sendable` with a justification comment.
4. **No force-unwraps, no `try!`, no `fatalError` in production paths.** Only in `#if DEBUG` assertions.
5. **Zero silent failures.** Every `catch { }` either logs or surfaces to the user.
6. **Crash-safe logging.** Logger uses a background write queue + best-effort fsync; never blocks UI; logger failure never crashes the app.
7. **All metrics are machine-parseable.** JSONL with a stable schema.
8. **Unit tests for every tricky piece.** Log rotation, metric recording, benchmark scoring, persona routing, safety-path refusals. `EidosTests` stays green on every commit.
9. **Fails-closed on safety.** Medical / self-harm / legal refusal paths are hardcoded string + regex triggers, never reach the LLM. Unit-tested.
10. **Feature flags, not branches.** `EidosFeatureFlags` — vision, audio, personas, each toggleable.

#### 8.2 — Diagnostics system

- `Eidos/Platform/Diagnostics/EidosLogger.swift` — central logger
  - Levels: `debug / info / warn / error / metric`
  - Categories: `model / chat / memory / rag / download / permission / ui / intent / skill / persona / crash`
  - Persists to `~/Documents/eidos/logs/YYYY-MM-DD.jsonl` (no rotation — keep all logs, per dev-mode spec)
  - Also mirrors to Apple unified log (visible in Console.app)
- `Eidos/Platform/Diagnostics/MetricsRecorder.swift` — per-generation metrics
  - TTFT (time-to-first-token)
  - Tokens out, tokens/sec
  - RSS memory before/peak/after (via `mach_task_basic_info`)
  - Thermal state during generation
  - CPU% via `proc_pidinfo` sampling every 1 s
  - GPU utilization (via `MTLCommandBuffer` timing where exposed)
- `Eidos/Platform/Diagnostics/FailureCategory.swift` — typed failure taxonomy
  - `modelLoad / modelGenerate / modelThermal / modelOOM / modelVisionFailed / modelAudioFailed`
  - `ragEmbed / ragRetrieve`
  - `memoryWrite / memoryRead / memoryCrystallize`
  - `downloadNetwork / downloadChecksum / downloadDiskFull`
  - `permissionDenied / audioSessionFailed / cameraAccessFailed`
  - `intentExecute / skillExecute / personaRouteFailed`
  - `unknown`
- `Eidos/Platform/Diagnostics/FeatureFlags.swift` — runtime toggles
  - `visionEnabled`, `audioEnabled`, `reasoningEnabled`, `personasEnabled`, `diagnosticsUIEnabled`
- **UI**: Settings → Diagnostics tab
  - Live log tail with filter by category/level
  - Metrics table (last 100 generations: TTFT, tok/s, RSS, thermal)
  - "Run Benchmarks" button → executes corpus → shows results
  - "Export All" button → zip of logs + metrics + benchmarks

#### 8.3 — Model dedupe audit

Scan every location Gemma files may have accumulated across prior sessions. Auto-delete everything except the current Mac (Designed for iPad) sandbox copy. Report reclaimed bytes.

Paths to sweep:
- `~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/gemma-*`
- `~/Library/Developer/Xcode/DerivedData/Eidos-*/Build/Products/**/Documents/gemma-*`
- `~/Library/Containers/com.hissamuddin.eidos/Data/Documents/gemma-*`
- `~/Downloads/gemma-*`
- `~/.cache/huggingface/hub/models--mlx-community--gemma-*`

#### 8.4 — Multimodal upgrade: `MLXVLM`

- Add `MLXVLM` to `project.yml` package products
- Rewrite `GemmaSession`:
  - `load(variant:)` uses VLM container (same model files, different loader)
  - `generate(messages:images:audio:reasoning:)` — unified multimodal entry point
  - Optional image is `[CGImage]` or `[UIImage]` array
  - Optional audio is `Data` (16 kHz mono PCM)
  - Optional reasoning flag triggers chain-of-thought prompt prefix
- Update `RAGPipeline`, `DigestGenerator`, `MemoryCrystallizer`, skills — they remain text-only and pass no image/audio; zero behavior change
- Update `Info.plist`: add `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`

#### 8.5 — Audio input: local voice path + native-audio bridge

- `Eidos/Platform/AudioCaptureService.swift` — records mic audio
  - 16 kHz mono PCM into an in-memory `Data` buffer
  - Voice Activity Detection (VAD) via `SFVoiceActivityDetector` (iOS 18+) for auto-stop on silence
  - Max clip cap: 30 s
  - Live waveform visualizer exposed via `@Observable` `rmsLevel`
  - **Audio never touches disk** — in-memory only, freed after generation
- `ChatInputBar` can store a captured PCM attachment and the chat/pipeline layers accept `audio: Data?` already.
- **Current shipping behavior**: `SpeechTranscriber` remains the default user voice path because the current `mlx-swift-lm` public API does not yet expose raw audio attachments. This is an upstream library boundary, not a missing Eidos pipeline.
- Once `mlx-swift-lm` exposes audio attachments, flip `GemmaSession.supportsNativeAudioInput`, route `audioViaGemmaEnabled` on by default, and then remove `NSSpeechRecognitionUsageDescription`.

#### 8.6 — Vision input

- `Eidos/Platform/VisionCaptureService.swift` — picks an image
  - Camera (via `UIImagePickerController` or AVCapture)
  - Photo library (via `PHPickerViewController`)
  - Screenshot-of-self (Eidos's own UI for meta queries)
- Wire into `ChatInputBar`: camera / photo buttons next to mic
- Image sent as `CGImage` to `GemmaSession.generate(images:)`
- Vision token budget: start at 280 (middle of supported: 70/140/280/560/1120), tune via benchmark

#### 8.7 — Chain-of-thought ("reasoning") mode

- `ReasoningMode.swift` — opt-in flag per generation call
- Used automatically for:
  - Digest generation (pulling across many data sources)
  - Persona dispatch (deciding which specialist handles a query)
  - Skill conflict resolution (when two skills both claim a query)
  - Benchmark's "reasoning" category prompts
- UI: a "think harder" toggle in the chat bar for user-initiated deep queries

#### 8.8 — Long-context memory packing

- Exploit Gemma 4's 128K context to load MORE memory in-prompt instead of aggressive RAG filtering
- Update `ContextBuilder` token budget from ~7 K → ~60 K (leaves headroom for output)
- Retrieval strategy becomes layered:
  - P0 always in-prompt
  - P1 always in-prompt
  - P2 RAG-filtered if relevance score > threshold
  - P3 RAG-filtered only if P2 empty
- Measure via benchmarks: does larger context improve coherence on long-memory queries? Does TTFT pay an unacceptable cost?

#### 8.9 — Benchmark corpus + runner

- `Eidos/Platform/Diagnostics/BenchmarkRunner.swift`
- 11 categories × ~4 prompts = ~44 prompts total
  - **Short chat** — TTFT, warm-up latency
  - **Long context** — 4K+ token input, coherence
  - **JSON / tool use** — structured output (critical for skills)
  - **RAG grounding** — retrieval + grounded answer
  - **Refusal** — medical, legal, violence, self-harm safety
  - **Vision** — OCR and scene understanding on bundled synthetic fixtures with stable rubrics
  - **Audio** — placeholder category retained, but skipped until native raw-audio input is exposed by `mlx-swift-lm`
  - **Multilingual** — English, Urdu, Arabic stays in-language
  - **Reasoning** — arithmetic, logic puzzles
  - **Hallucination probe** — empty-memory declines
  - **Vision — OCR** — screenshot → text
  - **Vision — scene understanding** — photo → description, counts, objects
  - **Vision — chart reading** — chart image → trend / value extraction
  - **Vision — handwriting** — photo of note → transcription
  - **Audio — transcription** — clip → text
  - **Audio — intent** — clip → intended action
  - **Audio — tone** — clip → detected mood/urgency
- Each prompt carries an expected-output rubric (regex + keyword + structural checks)
- Results exported as JSON + human-readable MD summary

#### 8.10 — Safety hardcodes (non-LLM)

- `Eidos/Platform/SafetyGate.swift` — pre-LLM intercept
  - Regex detectors for crisis language (self-harm, suicide, chest pain, severe bleeding)
  - Returns a hardcoded response with actual emergency resources (988 Lifeline US + locale lookups)
  - NEVER reaches Gemma — LLM can't override emergency routing
  - Unit-tested against a curated crisis-phrase corpus
- Applied in `RAGPipeline.send()` before any generation

**Milestone**: Diagnostics UI shows live metrics. Benchmark suite produces a scored report. Safety gate blocks crisis queries deterministically. Native image input works end-to-end. Voice input stays fully local and is explicitly documented as waiting on upstream raw-audio API support. All Phase 8 commits carry unit tests.

---

### Phase 10a — Web Search + Followed Topics (planned, post Phases 8+9)

**Vision (user, 2026-04-24)**: A fully local personalized AI that keeps the user current on topics they chose — sports scores, news, events, shows, anything. Sensitive data never eligible for outbound. Web access constrained and verifiable.

**Two use cases**:
1. **Proactive topic tracker** (primary, distinctive): user says "I follow the Lakers" once. Eidos saves that, fetches daily in the background, mentions updates in the morning briefing. User never has to ask.
2. **Reactive Q&A boost** (secondary): when Gemma can't answer from local knowledge and the query is scrubbable, fetch supporting context and use it as mini-RAG.

**Core privacy guarantees** (code-enforced, not promises):
- **Sensitive memory tier is compile-time fenced from the fetcher.** `FollowedTopic.topic: String` is the ONLY type that can reach the network layer. Sensitive memories cannot be typed as a follow-target. Enforced at the type system, not at runtime.
- **Single whitelisted hostname** (DuckDuckGo HTML endpoint). No cookies, no account, no API key.
- **TLS certificate pinning** on the endpoint; hard-fail on mismatch.
- **Every outbound request logged** and visible in Diagnostics → Network tab (to be built).
- **No user identity in any query.** Queries are generic topic names only ("Lakers score today").
- **Search results are treated as UNTRUSTED context.** Gemma is explicitly instructed never to execute instructions embedded in fetched content (prompt-injection defence).
- **Daily batched fetch** + jittered timing → frustrates pattern correlation.

**Components**:
- `FollowedTopicsManager` — `@Observable` class; adds/removes/lists topics; backed by a new `followed_topics` memory tier
- `WebSnapshotFetcher` — single-endpoint DuckDuckGo HTML scraper; strips to plain text; never passes sensitive tier types
- `EgressGuard.whitelistSearch()` — permeable layer, one hostname, cert-pinned
- `BGAppRefreshTask` — daily at user-configurable hour (defaults 6 am), refreshes all followed topics
- `PromptTemplates.systemPrompt` update — new `## Recently from your follows` block, UNTRUSTED marker on fetched content
- `DiagnosticsView → Network` tab — live log of every outbound request, editable followed-topics list

**UI flow**:
- First time user mentions something that looks follow-able in chat ("I love Tottenham", "keep me updated on AI news"), Eidos offers inline: *"Want me to track this?"* (Yes / No / Always Ask)
- Settings → Followed Topics manages the list (view, remove, edit refresh schedule)
- Morning briefing automatically includes the latest fetched updates

**Gate**: build AFTER Phase 9.5 ships to real users AND data shows users
repeatedly ask about current information Gemma doesn't know. If local handles
80 %+ of general queries well, web may be unnecessary polish.

**Marketing pitch**: *"Eidos is the only AI that pulls the web for topics YOU chose, on a schedule YOU set, shows you exactly what it fetched, and never tells anyone you asked."*

---

### Phase 10b — "JARVIS" Hybrid Compute (planned, post Phases 8+9)

**Vision (user, 2026-04-24)**: Eidos is fully private locally by default. When the user is online AND needs more brainpower than 2B Gemma provides, Eidos acts as a **privacy guardian** — redacting the query before it leaves, routing to a bigger cloud LLM, and **re-hydrating the answer locally** with the user's private context. The user sees exactly what went out, opts in per query. Net effect: better brainpower than ChatGPT-level apps while leaking dramatically less data.

**Three-path architecture**:

| Path | Trigger | Privacy |
|---|---|---|
| Local-only (Gemma) | Offline, or personal-data-in-query classified needed | Perfect |
| Cloud via redactor | Online + query scrubbable (factual, knowledge, code, reasoning) | Strong — cloud sees only the scrubbed query, re-hydration is local |
| Cloud with explicit consent | User approves per-query, data genuinely must go | Transparent — diff shown, audit-logged |

**Components** (defer until Phases 8 + 9 ship):
- `CloudLLMProvider` protocol — OpenAI / Anthropic / Gemini / local Ollama adapters
- `QueryClassifier` — local Gemma decides path per query
- `QueryRedactor` — 2-pass Gemma (strip PII → critique own redaction)
- `ConsentSheet` — diff view, one-tap approve/reject, log every decision
- `EgressGuard` whitelist — opt-in endpoints only
- BYOK (bring-your-own-key) setup in Settings, Keychain storage
- Audit log visible in Diagnostics

**Known-valid limitation**: queries that genuinely need private data in the prompt (summarize MY notes, write reply based on MY relationship) cannot be scrubbed. For those, the user explicitly opts in to send, or falls back to local-only.

**Marketing pitch**: *"When offline, Eidos is private. When online, Eidos is your **privacy guardian** to the world's smartest models. Scrubs your data before asking, shows what's going out, stitches answers back with your private context locally. No other AI app does this."*

**Gate**: don't build until the base product and Phase 9.5 are in users'
hands AND data shows local Gemma fails > 40% of queries. If local handles well
enough, skip cloud entirely.

---

### Phase 9 — Skills / Personas: PLANNED

**Goal**: Turn Eidos into a staff of specialists — master persona + on-device experts — each with its own voice, knowledge corpus, and memory slice, backed by Gemma 4 multimodal.

**Design decisions (locked 2026-04-23 with user)**:

- **Naming.** No "Doctor" / "Therapist" labels. Legal liability floor is too low. Use: `Health Companion`, `Reflection Partner`, `Fitness Coach`, `Nutrition Guide`, `Programmer`, `Tutor`, `Master`. Clinical-sounding titles are banned in user-visible copy.
- **Activation model.** Master-dispatch by default (one chat, router picks specialist). "Room mode" available for users who want to stay in one headspace — switchable in Settings.
- **Roster v1.** 5 specialists + 1 master (Health Companion, Fitness Coach, Nutrition Guide, Programmer, Tutor, Master). v2 may add user-defined personas.
- **Notification budget.** Max 3 notifications/day across ALL personas. Master arbitrates priority.
- **Onboarding.** Max 5 setup questions per persona + continuous passive learning.

#### 9.1 — Memory architecture for personas

```
~/Documents/eidos/
├── core/                         # read-by-all
│   ├── identity.md
│   ├── preferences.md
│   └── relationships.md
├── personas/
│   ├── fitness/
│   │   ├── profile.md            # goals, baseline, injuries
│   │   ├── sessions/2026-04-*.md
│   │   └── p0_core.md
│   ├── health-companion/
│   │   ├── profile.md
│   │   ├── medications.json      # STRUCTURED
│   │   ├── allergies.json
│   │   └── symptoms/2026-04-*.md
│   ├── nutrition/
│   │   ├── profile.md
│   │   ├── meals/2026-04-*.md
│   │   └── preferences.md
│   ├── programmer/
│   │   ├── profile.md
│   │   └── projects/
│   └── tutor/
│       ├── profile.md
│       └── subjects/
└── skill-index.json              # activated persona registry
```

Principles:
1. `core/` is read-by-all. Personas share identity, pronouns, preferred tone.
2. Each persona's directory is read-by-one by default. Cross-persona access requires explicit user opt-in per sensor/topic.
3. Structured JSON for anything with consequences (medications, allergies, PRs). Prose for context.
4. Reuse existing P0/P1/P2/P3 tiering per persona.

#### 9.2 — Knowledge corpora (grounded, not parametric)

Ship each persona with a bundled retrieval corpus so answers are grounded, not hallucinated:

- Fitness Coach → open exercise dataset (ExerciseDB, public-domain strength training references)
- Nutrition Guide → USDA FoodData Central subset
- Health Companion → MedlinePlus condition summaries (public domain)
- Programmer → cached language docs (Swift, Python, JS stdlib) — updatable
- Tutor → curated subject primers per topic area

Each corpus is 50–200 MB, loaded into a persona-scoped `VectorStore` index.

#### 9.3 — Persona router (the "Master")

- `Eidos/Skills/PersonaRouter.swift` — not a separate model, just Gemma with a routing prompt
- Classifies incoming query: `{fitness: 0.7, health: 0.2, nutrition: 0.1, master_generic: 0.0}`
- Activates top N personas (usually 1–2), loads their memory + corpus, generates response in chosen persona's voice
- Logs routing decision + confidence for diagnostics

#### 9.4 — Persona voices

Each persona has a locked system prompt containing:
- Identity, scope, and voice
- Enumerated allowed topics and forbidden topics
- Grounding rule: cite retrieved corpus + user memory, never invent
- Handoff protocol: on out-of-scope, explicitly escalate to Master or peer persona
- Safety overlay: Health Companion and Reflection Partner hard-refuse diagnosis, prescription, dosing, crisis handling (those go to `SafetyGate`)

#### 9.5 — Cross-persona consultation

- When Fitness answers "my knee hurts, should I run?", it internally queries Health Companion for recent injury log BEFORE generating
- Internal consultation = multi-turn generation pass that user doesn't see; final response is one coherent reply
- Shared event bus so ambient data (Location arrived at gym, Motion detected run) fans out to all subscribed personas

#### 9.6 — Persona-driven notifications

- Each persona can schedule notifications via `NotificationScheduler`, subject to the 3/day global budget
- Master does the arbitration: priority ranking across pending notifications, drops lowest on budget exhaust
- Examples:
  - Fitness: "Your usual gym time is 6 pm — still want to go?"
  - Health Companion: "Evening medication reminder" (only after user shared prescription)
  - Nutrition: "You tracked 22 g protein at lunch — dinner target ~40 g"

#### 9.7 — Vision + audio enablement for personas (requires Phase 8)

- Health Companion: photo of medication label → extracts drug + dose + schedule
- Fitness: photo of gym machine or form check → technique guidance
- Nutrition: photo of plate → food ID + USDA-grounded macro estimate
- Programmer: screenshot of error dialog → debugging without retyping
- Tutor: photo of homework problem → step-by-step
- All grounded in their knowledge corpus. All refuse out-of-scope.

#### 9.8 — Persona settings + UI

- New "Skills" tab (or a sheet from Home) — shows activated personas
- Per-persona toggle: activate, pause, delete
- Per-persona settings: data sharing, notification opt-in, voice on/off
- "Forget this persona" — deletes that persona's directory only, leaves others intact

#### 9.9 — Skill packs as monetization

- Free tier: Master + Fitness + Notes Helper
- Paid unlock: Health Companion, Nutrition Guide, Programmer, Tutor (one-time $2.99 each OR bundle $4.99/mo)
- Low marginal cost: each persona = system prompt + knowledge corpus + a handful of intent hooks
- **This is the revenue model that doesn't compromise the privacy promise.** Zero data egress; money comes from unlocks, not telemetry.

**Milestone**: User asks "I did a hard run today and my knee's sore" → Master routes to Fitness → Fitness internally consults Health Companion for injury history → returns one grounded answer citing the relevant corpus + user memory. Persona-driven notifications respect the global budget. Skill packs gated behind a purchase flow.

---

### Phase 9.5 — Ambient Agency + Trust Rails: PLANNED

**Goal**: Make Eidos feel like another part of the phone rather than a chat
app. The assistant should increasingly notice, prepare, suggest, and only then
act — so the best sessions have fewer commands, not smarter wording.

**Why this matters more than cloud/web**: Conventional AI apps already compete
on per-prompt intelligence. Eidos wins on continuity, initiative, and
verifiable action. If we add web search or cloud reasoning before ambient
agency, we risk turning Eidos into a smaller ChatGPT. If we add ambient agency
first, we deepen the moat that conventional AI apps cannot copy on iOS.

**Dependencies**:
- Phase 8 complete: diagnostics, safety gate, multimodal capture, long-context tuning
- Phase 9 complete: specialist skills, routing, persona-scoped memory
- 20–50 real users for 2+ weeks to calibrate notification budgets, routine confidence, and false-positive rates
- Stable local surfaces already shipped: widgets, live activities, App Intents, notifications, Home summaries

#### 9.5.1 — AuthorityProfile + ActionPolicyEngine

- Per-domain authority ladder: `observe / suggest / draft / confirm / auto_act`
- Scoped by person, place, time window, and action type
- Global kill switch, quiet hours, low-confidence fallback to suggest-only
- Power feature, not default: autonomy is graduated as trust is earned

#### 9.5.2 — Structured life state below Markdown audit view

Keep Markdown memory because it is readable and auditable. Add narrow,
structured stores for action-bearing concepts:

- `people` — relationship state, cadence, important details, pending loops
- `commitments` — promises, deadlines, waiting-fors, follow-ups
- `routines` — recurring patterns with confidence + decay
- `prepared_actions` — drafts, briefs, route suggestions, reminder candidates
- `receipts` — what Eidos suggested/did, why, and with what outcome

Do **not** force all ambient behavior through embeddings or prose parsing at
runtime. The Markdown layer remains the trust surface; the structured layer
drives reliable automation.

#### 9.5.3 — CommitmentLedger

- Structured store of promises, deadlines, follow-ups, and open loops
- Extracted from chat, calendar titles/notes, shared content, and accepted suggestions
- Powers "you said you'd send X", "you promised to follow up with Alex", and stale-open-loop nudges

#### 9.5.4 — PeopleGraph

- Per-contact state: relationship, last interaction, communication cadence,
  tone preference, known important details, pending loops
- Backed by Contacts + memory + share ingestion, not just freeform notes
- Enables relationship intelligence without turning Eidos into a manual CRM

#### 9.5.5 — RoutineGraph

- Learns recurring patterns by weekday / time / place with confidence + decay
- Examples: commute, gym windows, weekly calls, grocery runs, deep-work blocks
- Must degrade gracefully when routines drift; stale routines are worse than none

#### 9.5.6 — PreparationEngine

- Precomputes `PreparedAction` objects with TTLs: draft texts, meeting briefs,
  routes, grocery lists, reminder suggestions, follow-up nudges
- Default behavior is to prepare quietly; ask or act only when confidence and
  authority allow
- This is the core of "the less commands given, the better"

#### 9.5.7 — SurfaceRouter + AttentionBudget

- Chooses where value appears: widget, lock screen, live activity,
  notification, App Intent, Home card, or nowhere
- Prefers passive surfaces over alerts
- Daily / weekly caps, novelty decay, cooldowns after dismissals, escalation
  only for genuinely time-sensitive items
- Eidos must never become nagware

#### 9.5.8 — ReceiptCenter

- Every proactive suggestion or action gets a receipt: trigger, inputs,
  confidence, outcome, undo link, dismissal reason
- Receipts are the trust feature that conventional AI apps do not have
- Diagnostics should make these browsable, searchable, and exportable

#### 9.5.9 — SensitiveVault

- Biometric-gated tier for truly sensitive facts and documents
- Excluded from web/cloud/fetcher paths by type, not by convention
- Separate receipts and access logs
- Needed before Eidos can credibly become the place users trust with identity-level information

#### 9.5.10 — BackgroundTriggerMatrix

Allowed triggers only:
- App foreground / resume
- Time-of-day windows
- Calendar changes
- Significant location
- Motion transitions
- Charging windows
- Notification replies / widget interactions

No fantasy continuous agent. Design for precomputation inside iOS's real limits.

#### 9.5.11 — Autonomy ladder (product behavior)

1. Observe silently
2. Suggest once
3. Prepare a draft / route / brief
4. Ask for confirmation
5. Auto-act only after explicit per-domain opt-in and repeated success

#### 9.5.12 — Success metrics

- `% of useful days with zero chat turns`
- `PreparedAction` open / accept / dismiss rates
- Undo rate on autonomous actions
- Open-loop closure rate
- False-positive proactive suggestion rate
- Commands per retained weekly user trending down while retention stays flat or rises
- Share of users who graduate from `suggest` -> `confirm` -> `auto_act`

**Milestone**: Eidos notices the user has a meeting with Alex in 40 minutes,
remembers a promised follow-up, detects traffic deterioration, prepares the
meeting brief + route + reminder draft, surfaces one lock-screen card, and
logs exactly why. User does not need to open chat.

**Gate**: build after Phases 8 + 9 ship to real users. This phase takes
priority over cloud escalation work because it is the core moat.

---

## Architecture Overview (Updated)

```
┌──────────────────────────────────────────────────────────┐
│                       EidosApp                            │
│                  (SwiftUI @main, iOS 26+)                 │
├──────────────┬──────────────┬──────────────┬──────────────┤
│  ChatView    │  HomeView    │  MemoryBrowse│ SettingsView │
│  SkillsTab   │  DigestCard  │  KBBrowser   │ Diagnostics  │
│  IngestView  │  LiveActivity│  Widget      │ FeatureTour  │
├──────────────┴──────────────┴──────────────┴──────────────┤
│                    AppContainer (DI)                       │
├───────────────────────────────────────────────────────────┤
│                  PersonaRouter (Master)                    │
│    Classify intent → activate specialist → synthesize     │
├───────────────────────────────────────────────────────────┤
│                     SafetyGate                             │
│  Pre-LLM intercept: crisis / harmful → hardcoded response │
├───────────────────────────────────────────────────────────┤
│                    RAG Pipeline                            │
│  Memory Load → Context Build → Gemma Generate             │
│  (text + image + audio + reasoning) → Skill Dispatch      │
│  → Memory Update → Crystallize                            │
├────────┬─────────┬─────────┬─────────┬──────────┬─────────┤
│ Memory │ Skills /│ Know-   │ Infer-  │ Platform │ Diag-   │
│ System │ Personas│ ledge   │ ence    │ Sources  │ nostics │
│        │         │         │         │          │         │
│ Index  │ Fitness │ SwiftD. │ MLX     │ EventKit │ Logger  │
│ MD     │ Health  │ Vector  │ Gemma 4 │ Contacts │ Metrics │
│ Decay  │ Nutri.  │ Embed.  │ VLM     │ HealthKit│ Bench.  │
│ Crystal│ Prog.   │ Corpora │ Audio   │ Location │ Failure │
│ 128K   │ Tutor   │ RRF     │ Vision  │ Motion   │ Flags   │
│ packing│ Master  │ Hybrid  │ CoT     │ Music    │ CSV/JSON│
├────────┴─────────┴─────────┴─────────┴──────────┴─────────┤
│           Audio / Vision / Text Capture                    │
│  AudioCaptureService (16 kHz + VAD, in-mem only)          │
│  VisionCaptureService (camera / photo / screen)            │
│  (fallback) SpeechTranscriber — thermal-throttle only     │
├───────────────────────────────────────────────────────────┤
│                  Proactive Engine                          │
│  Routine → Digest → Notifications (3/day global budget)   │
│  Relationship → Nudges → Widgets / Live Activities        │
├───────────────────────────────────────────────────────────┤
│              EgressGuard (URLProtocol)                     │
│  Zero egress after onboarding — enforced by code          │
└───────────────────────────────────────────────────────────┘
    ↕
┌───────────────────────────────────────────────────────────┐
│   Extensions: ShareExtension, Widget, ControlWidgets      │
│   App Intents: 23 intents, 10 Siri phrases (iOS max)      │
│   Shortcuts: 10 pre-built recipes, open to user authoring │
└───────────────────────────────────────────────────────────┘
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

Conventional AI apps optimize for answer quality per prompt. Eidos optimizes
for continuity, initiative, and receipts. The north-star is not "more chat
minutes"; it is "more life handled with fewer commands."

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
DONE:       Phase 0–8 — Core product, diagnostics, multimodal image path, Markdown response rendering, 192 tests green
NOW:        Phase 9 — Skills / Personas
              1. Memory architecture (per-persona dirs)
              2. Knowledge corpora (Fitness/Nutrition/Health/Programmer/Tutor)
              3. PersonaRouter (Master dispatch)
              4. Per-persona system prompts + voices
              5. Cross-persona consultation protocol
              6. Persona-driven notifications (global 3/day budget)
              7. Vision + audio per persona (leverages Phase 8)
              8. Skills tab UI + per-persona settings
              9. Skill packs monetization flow
THEN:       Phase 9.5 — Ambient Agency + Trust Rails
              1. AuthorityProfile + ActionPolicyEngine
              2. CommitmentLedger + PeopleGraph + RoutineGraph
              3. PreparationEngine + PreparedAction TTLs
              4. SurfaceRouter + AttentionBudget
              5. ReceiptCenter + undo / audit UI
              6. SensitiveVault + biometric gating
              7. BackgroundTriggerMatrix tuning on real devices
OPTIONAL:   Phase 10a — Web Search + Followed Topics
OPTIONAL:   Phase 10b — "JARVIS" Hybrid Compute
LATER:      Device validation, TestFlight, public launch, Android recovery of full agent vision
```

Each phase is shippable independently. Phase 8 alone (multimodal + diagnostics) is a massive capability uplift. Phase 9 turns Eidos from a chat app into a staff of specialists.

---

## How We Work

- **This file is the source of truth.** Any new major feature, new file, new package, or design pivot gets reflected here in the same commit.
- **CLAUDE.md points here.** Claude reads this file before making design decisions.
- **Deferred items are explicit.** Every deferred feature lists why and when it comes back.
- **Engineering bar** (§8.1) applies to all new code, regardless of phase.
- **Benchmarks gate shipping.** Before any release candidate, full benchmark corpus must pass rubric + no safety-gate regressions.
