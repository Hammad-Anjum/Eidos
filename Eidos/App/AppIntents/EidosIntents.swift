import Foundation
import AppIntents

// Intents are the API surface for Siri, Shortcuts, Action Button, and
// Spotlight. This file aggressively exposes as many granular actions
// as we can because breadth of intents is the category's moat — no
// other on-device-AI iOS app ships > 10, and iOS Shortcuts power users
// will compose these into automations we can't anticipate.
//
// Design principle: each intent either
//   (a) opens the app at a specific tab / state, or
//   (b) writes a piece of data (reminder / memory / note) that the app
//       picks up on next launch — no Gemma needed, runs without opening.
// Gemma-dependent intents (summarise, draft-reply, digest) require
// openAppWhenRun = true because the model only runs in the main process.

// MARK: - Navigation

struct OpenEidosChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Eidos"
    static let description = IntentDescription("Open Eidos and start a conversation.", categoryName: "Chat")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

struct OpenEidosMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Browse my memory"
    static let description = IntentDescription("Open the Eidos memory browser.", categoryName: "Memory")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.memory)
        return .result()
    }
}

struct OpenKnowledgeBaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Open my knowledge base"
    static let description = IntentDescription("Browse saved notes and imports.", categoryName: "Knowledge")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.knowledgeBase)
        return .result()
    }
}

// MARK: - Briefing / digest

struct GenerateDigestIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's briefing"
    static let description = IntentDescription("Generate and read your morning briefing from Eidos.", categoryName: "Briefing")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.home)
        return .result(dialog: IntentDialog("Opening your Eidos briefing."))
    }
}

struct WeekAheadIntent: AppIntent {
    static let title: LocalizedStringResource = "Week ahead"
    static let description = IntentDescription("Look at what's coming up in the next 7 days.", categoryName: "Briefing")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.home)
        return .result()
    }
}

// MARK: - Memory — no-launch (work without opening app)

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Save a note"
    static let description = IntentDescription("Save a note to your Eidos memory. Runs without opening the app.", categoryName: "Memory")
    static let openAppWhenRun = false

    @Parameter(title: "Note", description: "What to remember.")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = MemoryManager()
        let title = String(content.prefix(40))
        let entry = MemoryEntry(
            tier: .topic, title: title, body: content,
            priority: .p3, tags: ["siri-capture"]
        )
        _ = try? await manager.save(entry)
        return .result(dialog: IntentDialog("Noted: \(title)"))
    }
}

struct SearchMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search memory"
    static let description = IntentDescription("Find memory entries mentioning a keyword.", categoryName: "Memory")
    static let openAppWhenRun = false

    @Parameter(title: "Keyword")
    var keyword: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let manager = MemoryManager()
        try? await manager.rebuildIndex()
        let lowered = keyword.lowercased()
        let all = await manager.index.all
        let hits = all.filter {
            $0.title.lowercased().contains(lowered)
                || $0.tags.contains(where: { $0.lowercased().contains(lowered) })
        }
        if hits.isEmpty {
            return .result(value: "", dialog: IntentDialog("Nothing about \(keyword) in my memory."))
        }
        let summary = hits.prefix(5).map(\.title).joined(separator: " · ")
        return .result(value: summary, dialog: IntentDialog("\(hits.count) matches: \(summary)"))
    }
}

struct WhatDoIKnowAboutIntent: AppIntent {
    static let title: LocalizedStringResource = "What do I know about…"
    static let description = IntentDescription("Pull everything Eidos remembers about a person or topic.", categoryName: "Memory")
    static let openAppWhenRun = true

    @Parameter(title: "Topic or person")
    var topic: String

    @MainActor
    func perform() async throws -> some IntentResult {
        // Route to a dedicated "What I know about" view in the app —
        // the app handles the retrieval + Gemma synthesis.
        UserDefaults.standard.set(topic, forKey: "eidos.pendingKnowledgeQuery")
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.memory)
        return .result()
    }
}

struct MarkImportantIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember this forever"
    static let description = IntentDescription("Save something as a P1 core memory that never auto-expires.", categoryName: "Memory")
    static let openAppWhenRun = false

    @Parameter(title: "Fact")
    var fact: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = MemoryManager()
        let entry = MemoryEntry(
            tier: .coreIdentity,
            title: String(fact.prefix(40)),
            body: fact,
            priority: .p1,
            tags: ["core", "siri-capture"]
        )
        _ = try? await manager.save(entry)
        return .result(dialog: IntentDialog("Saved to core memory."))
    }
}

struct FlagPriorityIntent: AppIntent {
    static let title: LocalizedStringResource = "Flag a priority"
    static let description = IntentDescription("Record something as this week's active priority.", categoryName: "Memory")
    static let openAppWhenRun = false

    @Parameter(title: "Priority")
    var summary: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = MemoryManager()
        let entry = MemoryEntry(
            tier: .activePriorities,
            title: String(summary.prefix(40)),
            body: summary,
            priority: .p2,
            tags: ["siri-capture"]
        )
        _ = try? await manager.save(entry)
        return .result(dialog: IntentDialog("Flagged."))
    }
}

struct RecentMemoriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Recent memories"
    static let description = IntentDescription("Show your five most recently touched memory entries.", categoryName: "Memory")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let manager = MemoryManager()
        try? await manager.rebuildIndex()
        let top = await manager.index.topK(5)
        let summary = top.map(\.title).joined(separator: " · ")
        let message = summary.isEmpty ? "No recent memories." : summary
        return .result(value: summary, dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Commitments (promise tracking)

struct LogCommitmentIntent: AppIntent {
    static let title: LocalizedStringResource = "I said I'd…"
    static let description = IntentDescription("Log a commitment Eidos should remind you about.", categoryName: "Commitments")
    static let openAppWhenRun = false

    @Parameter(title: "What you promised")
    var promise: String

    @Parameter(title: "To whom", description: "Person's name, optional.")
    var person: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = MemoryManager()
        let body: String
        if let person, !person.isEmpty {
            body = "Told \(person): \(promise)"
        } else {
            body = promise
        }
        let entry = MemoryEntry(
            tier: .activePriorities,
            title: "Commitment: \(String(promise.prefix(30)))",
            body: body,
            priority: .p2,
            tags: ["commitment", "siri-capture"]
        )
        _ = try? await manager.save(entry)
        return .result(dialog: IntentDialog("I'll remember."))
    }
}

// MARK: - Reminders / calendar

struct CreateReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Create a reminder"
    static let description = IntentDescription("Create a reminder in the Reminders app.", categoryName: "Productivity")
    static let openAppWhenRun = false

    @Parameter(title: "What to remind you about")
    var title: String

    @Parameter(title: "Due date", description: "Optional.")
    var dueDate: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let source = CalendarSource()
        _ = await source.requestRemindersPermission()
        do {
            _ = try await source.createReminder(title: title, dueDate: dueDate)
            if let dueDate {
                let f = DateFormatter()
                f.dateFormat = "EEE d MMM, h:mm a"
                return .result(dialog: IntentDialog("Reminder added: \(title), due \(f.string(from: dueDate))."))
            }
            return .result(dialog: IntentDialog("Reminder added: \(title)."))
        } catch {
            return .result(dialog: IntentDialog("Couldn't create the reminder."))
        }
    }
}

struct WhatsOnTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on today"
    static let description = IntentDescription("Read your calendar for today.", categoryName: "Calendar")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let source = CalendarSource()
        _ = await source.requestEventsPermission()
        let events = await source.fetchEvents(daysAhead: 1)
        if events.isEmpty {
            return .result(value: "", dialog: IntentDialog("Nothing on your calendar today."))
        }
        let summary = events.prefix(5).map(\.readableDescription).joined(separator: "; ")
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct NextUpIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Read your next calendar event.", categoryName: "Calendar")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let source = CalendarSource()
        _ = await source.requestEventsPermission()
        let events = await source.fetchEvents(daysAhead: 2)
        let now = Date()
        guard let next = events.first(where: { $0.startDate > now }) else {
            return .result(value: "", dialog: IntentDialog("Nothing scheduled."))
        }
        return .result(value: next.readableDescription, dialog: IntentDialog(stringLiteral: next.readableDescription))
    }
}

struct OpenRemindersIntent: AppIntent {
    static let title: LocalizedStringResource = "Open reminders"
    static let description = IntentDescription("Read your open reminders.", categoryName: "Productivity")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let source = CalendarSource()
        _ = await source.requestRemindersPermission()
        let reminders = await source.fetchIncompleteReminders()
        if reminders.isEmpty {
            return .result(value: "", dialog: IntentDialog("No open reminders."))
        }
        let summary = reminders.prefix(5).map(\.title).joined(separator: "; ")
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - Action skills (pass to main app for confirmation)

struct SendWhatsAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Send a WhatsApp message"
    static let description = IntentDescription("Prepare a WhatsApp message for confirmation.", categoryName: "Messaging")
    static let openAppWhenRun = true

    @Parameter(title: "Phone number", description: "International format.")
    var phone: String

    @Parameter(title: "Message")
    var message: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let draft: [String: String] = ["phone": phone, "text": message]
        UserDefaults.standard.set(draft, forKey: "eidos.pendingWhatsAppDraft")
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

struct SendSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Send a text"
    static let description = IntentDescription("Prepare an SMS for confirmation.", categoryName: "Messaging")
    static let openAppWhenRun = true

    @Parameter(title: "Phone number")
    var phone: String

    @Parameter(title: "Message")
    var body: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let draft: [String: String] = ["phone": phone, "body": body]
        UserDefaults.standard.set(draft, forKey: "eidos.pendingSMSDraft")
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

struct SendEmailFromIntent: AppIntent {
    static let title: LocalizedStringResource = "Send an email"
    static let description = IntentDescription("Draft an email to a contact.", categoryName: "Messaging")
    static let openAppWhenRun = true

    @Parameter(title: "To")
    var to: String

    @Parameter(title: "Subject")
    var subject: String?

    @Parameter(title: "Body")
    var body: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        var draft: [String: String] = ["to": to]
        if let subject { draft["subject"] = subject }
        if let body { draft["body"] = body }
        UserDefaults.standard.set(draft, forKey: "eidos.pendingEmailDraft")
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

struct CallPersonIntent: AppIntent {
    static let title: LocalizedStringResource = "Call someone"
    static let description = IntentDescription("Prepare a phone call for confirmation.", categoryName: "Messaging")
    static let openAppWhenRun = true

    @Parameter(title: "Phone number")
    var phone: String

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(phone, forKey: "eidos.pendingCallDraft")
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

struct NavigateToIntent: AppIntent {
    static let title: LocalizedStringResource = "Navigate to"
    static let description = IntentDescription("Open Maps with directions to a place.", categoryName: "Navigation")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: String

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(destination, forKey: "eidos.pendingNavigateDraft")
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
        return .result()
    }
}

// MARK: - Ambient captures (user-trigger-able from Shortcuts automations)

struct LogAppUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log app usage to Eidos"
    static let description = IntentDescription("Lets a Shortcuts automation tell Eidos when you open a specific app. Build an automation: 'When App X is opened → Run this intent'.", categoryName: "Ambient")
    static let openAppWhenRun = false

    @Parameter(title: "App name")
    var appName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = MemoryManager()
        let entry = MemoryEntry(
            tier: .recentSession,
            title: "Opened \(appName)",
            body: "User opened \(appName) at \(Date().formatted())",
            priority: .p4,
            tags: ["app-log", appName.lowercased()]
        )
        _ = try? await manager.save(entry)
        return .result()
    }
}

struct LogLocationArrivalIntent: AppIntent {
    static let title: LocalizedStringResource = "Log arrival at place"
    static let description = IntentDescription("From a Shortcuts automation triggered when you arrive somewhere.", categoryName: "Ambient")
    static let openAppWhenRun = false

    @Parameter(title: "Place name")
    var place: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = MemoryManager()
        let entry = MemoryEntry(
            tier: .recentSession,
            title: "Arrived at \(place)",
            body: "Arrived at \(place) at \(Date().formatted())",
            priority: .p4,
            tags: ["location", place.lowercased()]
        )
        _ = try? await manager.save(entry)
        return .result()
    }
}

struct AmbientJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Journal a moment"
    static let description = IntentDescription("Drop a one-line reflection into Eidos memory.", categoryName: "Reflection")
    static let openAppWhenRun = false

    @Parameter(title: "Reflection")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = MemoryManager()
        let entry = MemoryEntry(
            tier: .recentSession,
            title: "Moment: \(String(text.prefix(30)))",
            body: text,
            priority: .p3,
            tags: ["journal", "reflection"]
        )
        _ = try? await manager.save(entry)
        return .result(dialog: IntentDialog("Noted."))
    }
}
