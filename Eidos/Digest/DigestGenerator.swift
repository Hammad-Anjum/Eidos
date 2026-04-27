import Foundation

/// Produces a short natural-language morning briefing from the user's
/// calendar, reminders, and recent memory highlights. Streams tokens so
/// `HomeView` can render progressively.
@MainActor
final class DigestGenerator {

    private let calendarSource: CalendarSource
    private let knowledgeRepo: KnowledgeRepository
    private let memoryManager: MemoryManager
    private let gemma: GemmaSession

    init(
        calendarSource: CalendarSource,
        knowledgeRepo: KnowledgeRepository,
        memoryManager: MemoryManager,
        gemma: GemmaSession
    ) {
        self.calendarSource = calendarSource
        self.knowledgeRepo = knowledgeRepo
        self.memoryManager = memoryManager
        self.gemma = gemma
    }

    /// Gathers today's context and streams a briefing from Gemma.
    /// Returns the full text when streaming completes.
    func generate() async throws -> AsyncThrowingStream<String, Error> {
        let context = await gatherContext()
        let messages: [[String: String]] = [
            ["role": "system", "content": DigestGenerator.systemPrompt],
            ["role": "user", "content": context],
        ]
        return try await gemma.generate(messages: messages)
    }

    /// Non-streaming variant — convenience for the Home view, which just
    /// waits for the full string.
    func generateText() async throws -> String {
        let stream = try await generate()
        var buffer = ""
        for try await chunk in stream { buffer += chunk }
        return buffer
    }

    // MARK: - Context gathering

    private func gatherContext() async -> String {
        let todayEvents = await calendarSource.fetchEvents(daysAhead: 1)
        let allWeek = await calendarSource.fetchEvents(daysAhead: 7)
        let todayIDs = Set(todayEvents.map(\.id))
        let upcomingEvents = Array(
            allWeek.filter { !todayIDs.contains($0.id) }.prefix(3)
        )
        let reminders = await calendarSource.fetchIncompleteReminders()

        // Top memory highlights — active priorities + P1 core identity.
        let p1 = await memoryManager.index.records(priority: .p1)
        let active = await memoryManager.index.records(tier: .activePriorities)
        var memoryLines: [String] = []
        for rec in (p1 + active).prefix(5) {
            memoryLines.append("• \(rec.title)")
        }

        var lines: [String] = []
        lines.append("Today: \(dateString())")

        let todayLabel = "\n**Today's calendar:**"
        if todayEvents.isEmpty {
            lines.append("\(todayLabel) Nothing scheduled today.")
        } else {
            lines.append(todayLabel)
            lines.append(contentsOf: todayEvents.prefix(5).map { "• \($0.readableDescription)" })
        }

        if !upcomingEvents.isEmpty {
            lines.append("\n**Upcoming this week:**")
            lines.append(contentsOf: upcomingEvents.map { "• \($0.readableDescription)" })
        }

        let pendingReminders = reminders.prefix(5)
        if !pendingReminders.isEmpty {
            lines.append("\n**Open reminders:**")
            lines.append(contentsOf: pendingReminders.map { "• \($0.title)" })
        }

        if !memoryLines.isEmpty {
            lines.append("\n**From memory:**")
            lines.append(contentsOf: memoryLines)
        }

        lines.append("\nGenerate a warm, concise 3-4 sentence morning briefing. Mention only items above. Don't invent anything.")
        return lines.joined(separator: "\n")
    }

    private func dateString() -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: Date())
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are Eidos, writing the user's morning briefing. Be concise (3-4 \
    sentences), warm, and personal. Only reference items explicitly listed \
    in the user's message — never fabricate events, reminders, or notes.
    """
}
