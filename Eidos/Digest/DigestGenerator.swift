import Foundation

@MainActor
final class DigestGenerator {
    private let calendarSource: CalendarSource
    private let knowledgeRepo: KnowledgeRepository
    private let gemma: GemmaSession

    init(calendarSource: CalendarSource, knowledgeRepo: KnowledgeRepository, gemma: GemmaSession) {
        self.calendarSource = calendarSource
        self.knowledgeRepo = knowledgeRepo
        self.gemma = gemma
    }

    /// Generates a morning briefing. Phase 4 implementation fetches today's
    /// calendar events + recent notes and streams them through Gemma.
    func generate() async throws -> String {
        // TODO(phase 4)
        ""
    }
}
