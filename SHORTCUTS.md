# Eidos × iOS Shortcuts — automation recipes

Every Eidos intent in `Eidos/App/AppIntents/EidosIntents.swift` is
available inside the iOS **Shortcuts** app. iOS power users can wire
these into automations that trigger on time, location, Focus mode,
NFC tag, or opening a specific app.

This file documents the recipes we ship as pre-built `.shortcut`
files (dropped into `/Shortcuts/` — opening a `.shortcut` file on
iOS installs it automatically).

**Why this matters**: third-party apps cannot read what's on your
screen, what you're listening to in Spotify, what you're texting.
iOS Shortcuts Automations are the ONE channel through which the user
themself lets us know. We turn Eidos into the nervous system of their
phone, with their explicit consent per trigger.

## Recipes to ship with the app

### 1. "Morning routine"
**Trigger**: 7:00am every weekday
**Actions**:
1. Get Weather
2. `GenerateDigestIntent` (Eidos)
3. Show notification

### 2. "Voice memo to memory"
**Trigger**: user runs manually (or binds to Action Button)
**Actions**:
1. Dictate Text
2. `AmbientJournalIntent` — text: (dictated result)

### 3. "Log Instagram time"
**Trigger**: When Instagram is opened
**Actions**:
1. `LogAppUsageIntent` — appName: "Instagram"
(Eidos can later surface "you opened Instagram 12 times today" in the digest.)

### 4. "Arriving at work"
**Trigger**: When I arrive at Work
**Actions**:
1. `LogLocationArrivalIntent` — place: "Work"
2. Optional: `GenerateDigestIntent` (refreshes briefing with today's focus)

### 5. "Arriving at gym"
**Trigger**: When I arrive at Gym
**Actions**:
1. `LogLocationArrivalIntent` — place: "Gym"

### 6. "Leaving home"
**Trigger**: When I leave Home
**Actions**:
1. `NextUpIntent` (speaks your next event)
2. If event has location: `NavigateToIntent` — destination: (event location)

### 7. "Pre-meeting prep"
**Trigger**: 5 minutes before any calendar event
**Actions**:
1. `WhatDoIKnowAboutIntent` — topic: (event organizer)
2. Speak result

### 8. "End of day reflection"
**Trigger**: 10:00pm every day
**Actions**:
1. Ask for Input: "How was today?"
2. `AmbientJournalIntent` — text: (input)

### 9. "Focus on — writing"
**Trigger**: user runs manually
**Actions**:
1. Set Focus: Do Not Disturb, 90 minutes
2. `AmbientJournalIntent` — text: "Starting writing sprint"

### 10. "Sent a message I want to remember"
**Trigger**: user runs manually (or swipe-and-select in Messages)
**Actions**:
1. Get Text Input (or get selected Message)
2. `AddNoteIntent` — content: "Sent to X: (text)"

## Intent catalogue (for Shortcut building)

| Intent | Parameters | Use case |
|---|---|---|
| `OpenEidosChatIntent` | — | Jump to chat |
| `OpenEidosMemoryIntent` | — | Jump to memory browser |
| `OpenKnowledgeBaseIntent` | — | Jump to knowledge base |
| `GenerateDigestIntent` | — | Open today's briefing |
| `WeekAheadIntent` | — | Open week view |
| `AddNoteIntent` | content | Drop a quick note |
| `SearchMemoryIntent` | keyword | Search by title/tag |
| `WhatDoIKnowAboutIntent` | topic | Full memory + KB recall |
| `MarkImportantIntent` | fact | Save as P1 core memory |
| `FlagPriorityIntent` | summary | Save as this-week priority |
| `RecentMemoriesIntent` | — | List 5 most recent |
| `LogCommitmentIntent` | promise, person | Track a promise you made |
| `CreateReminderIntent` | title, dueDate | Create a reminder |
| `WhatsOnTodayIntent` | — | Read today's calendar |
| `NextUpIntent` | — | Next calendar event |
| `OpenRemindersIntent` | — | List open reminders |
| `SendWhatsAppIntent` | phone, message | Draft a WhatsApp |
| `SendSMSIntent` | phone, body | Draft an SMS |
| `SendEmailFromIntent` | to, subject, body | Draft an email |
| `CallPersonIntent` | phone | Prepare a call |
| `NavigateToIntent` | destination | Open Maps |
| `LogAppUsageIntent` | appName | Ambient: app open |
| `LogLocationArrivalIntent` | place | Ambient: arrival |
| `AmbientJournalIntent` | text | Journal entry |

23 intents. Every one appears in Shortcuts' action picker under
**Eidos**. Users can compose them freely.

## Action Button (iPhone 15 Pro+)

Settings → Action Button → Shortcut → choose any Eidos shortcut.
Press → it runs. No app launch needed for `openAppWhenRun = false`
intents (those marked "no-launch" in the intent's static properties).
