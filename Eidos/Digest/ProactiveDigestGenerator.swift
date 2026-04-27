import Foundation

/// Structured result of a proactive digest pass. Separates "what the model
/// should render" (signals) from "what the user reads" (briefingText).
struct DigestSnapshot: Sendable {
    var briefingText: String
    var signals: ProactiveSignals
}

/// Raw inputs gathered before we ask Gemma to narrate. Surfacing these
/// lets the UI render structured cards alongside the paragraph and
/// lets the notification show a richer preview.
struct ProactiveSignals: Sendable {
    var todayEvents: [CalendarEvent]
    var upcomingEvents: [CalendarEvent]
    var openReminders: [Reminder]
    var memoryHighlights: [MemoryIndexRecord]
    var health: HealthInsight
    /// Derived nudges — stale memories that look like promises or deadlines.
    var nudges: [Nudge]

    struct Nudge: Sendable, Equatable, Identifiable {
        let id: String
        var title: String
        var detail: String
    }

    var hasAnything: Bool {
        !todayEvents.isEmpty || !upcomingEvents.isEmpty
            || !openReminders.isEmpty || !memoryHighlights.isEmpty
            || !nudges.isEmpty
    }
}

/// Proactive version of the morning digest. Same interface as
/// `DigestGenerator` but also pulls HealthKit + generates nudges from
/// memory decay. The result is both a narrated paragraph (via Gemma) and
/// a structured `ProactiveSignals` — the UI uses both.
@MainActor
final class ProactiveDigestGenerator {

    private let calendarSource: CalendarSource
    private let memoryManager: MemoryManager
    private let healthSource: HealthSource
    private let gemma: GemmaSession

    init(
        calendarSource: CalendarSource,
        memoryManager: MemoryManager,
        healthSource: HealthSource,
        gemma: GemmaSession
    ) {
        self.calendarSource = calendarSource
        self.memoryManager = memoryManager
        self.healthSource = healthSource
        self.gemma = gemma
    }

    // MARK: - Public API

    /// Gathers signals, asks Gemma for a paragraph, returns both.
    /// Callers can use `signals` directly without waiting for narration.
    func generate() async throws -> DigestSnapshot {
        let signals = await gatherSignals()
        let briefing = try await narrate(signals)
        return DigestSnapshot(briefingText: briefing, signals: signals)
    }

    /// Signals-only variant — cheap, no model call. Useful for the
    /// notification preview and for widget timelines later.
    func signalsOnly() async -> ProactiveSignals {
        await gatherSignals()
    }

    // MARK: - Signal gathering

    private func gatherSignals() async -> ProactiveSignals {
        let todayEvents = await calendarSource.fetchEvents(daysAhead: 1)
        let allWeek = await calendarSource.fetchEvents(daysAhead: 7)
        let todayIDs = Set(todayEvents.map(\.id))
        let upcomingEvents = Array(
            allWeek.filter { !todayIDs.contains($0.id) }.prefix(3)
        )
        let openReminders = await calendarSource.fetchIncompleteReminders()
        let health = await healthSource.latestInsight()

        // Memory highlights: P1 + active priorities.
        let p1 = await memoryManager.index.records(priority: .p1)
        let active = await memoryManager.index.records(tier: .activePriorities)
        let highlights = Array((p1 + active).prefix(5))

        // Nudges: stale active_priorities entries (haven't been touched in >7 days).
        // These are "you flagged this as urgent but haven't revisited it."
        let stale = await memoryManager.index.stale(olderThanDays: 7, tier: .activePriorities)
        let nudges = stale.prefix(5).map { record in
            ProactiveSignals.Nudge(
                id: record.id.uuidString,
                title: "Reminder: \(record.title)",
                detail: "You flagged this \(Self.daysAgo(record.lastAccessedAt)) days ago and haven't followed up."
            )
        }

        return ProactiveSignals(
            todayEvents: todayEvents,
            upcomingEvents: upcomingEvents,
            openReminders: openReminders,
            memoryHighlights: highlights,
            health: health,
            nudges: Array(nudges)
        )
    }

    // MARK: - Narration

    private func narrate(_ signals: ProactiveSignals) async throws -> String {
        guard signals.hasAnything || signals.health.readableLine != "No health data available." else {
            return "Nothing on your plate today. Quiet day ahead."
        }

        var userBody: [String] = []
        userBody.append("Today: \(Self.dateString())")

        if signals.todayEvents.isEmpty {
            userBody.append("\n**Today's calendar:** Nothing scheduled today.")
        } else {
            userBody.append("\n**Today's calendar:**")
            userBody.append(contentsOf: signals.todayEvents.prefix(5).map { "• \($0.readableDescription)" })
        }
        if !signals.upcomingEvents.isEmpty {
            userBody.append("\n**Upcoming this week:**")
            userBody.append(contentsOf: signals.upcomingEvents.map { "• \($0.readableDescription)" })
        }
        if !signals.openReminders.isEmpty {
            userBody.append("\n**Open reminders:**")
            userBody.append(contentsOf: signals.openReminders.prefix(5).map { "• \($0.title)" })
        }
        if !signals.memoryHighlights.isEmpty {
            userBody.append("\n**From memory:**")
            userBody.append(contentsOf: signals.memoryHighlights.map { "• \($0.title)" })
        }
        if !signals.nudges.isEmpty {
            userBody.append("\n**Needs attention:**")
            userBody.append(contentsOf: signals.nudges.map { "• \($0.title) — \($0.detail)" })
        }
        if !signals.health.readableLine.contains("No health") {
            userBody.append("\n**Yesterday:** \(signals.health.readableLine)")
        }
        userBody.append("\nGenerate a warm, concise 3-5 sentence morning briefing. Mention only items above. Don't invent anything.")

        let messages: [[String: String]] = [
            ["role": "system", "content": DigestGenerator.systemPrompt],
            ["role": "user", "content": userBody.joined(separator: "\n")],
        ]

        let stream = try await gemma.generate(messages: messages)
        var buffer = ""
        for try await chunk in stream { buffer += chunk }
        return buffer
    }

    // MARK: - Utilities

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: Date())
    }

    private static func daysAgo(_ date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) / 86_400))
    }
}
