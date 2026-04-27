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
        let daysAhead = parameters["days_ahead"]?.intValue ?? 7
        let events = await source.fetchEvents(daysAhead: daysAhead)
        if events.isEmpty {
            return .success("No events scheduled in the next \(daysAhead) days.")
        }
        let lines = events.prefix(20).map { "• \($0.readableDescription)" }
        return .success(lines.joined(separator: "\n"))
    }
}
