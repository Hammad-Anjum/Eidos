import Foundation

struct CalendarSkill: Skill {
    let name = "get_calendar_events"
    let description = "Fetch upcoming calendar events. Use when the user asks about their schedule, meetings, or what is happening today or this week."
    let parametersSchema = #"{"type":"object","properties":{"days_ahead":{"type":"integer","default":7}}}"#

    private let source: CalendarSource

    init(source: CalendarSource) {
        self.source = source
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // TODO(phase 4)
        .failure("CalendarSkill not yet implemented")
    }
}
