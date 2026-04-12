import Foundation

struct RemindersSkill: Skill {
    let name = "get_reminders"
    let description = "Fetch the user's incomplete reminders. Use when the user asks what they need to do or about their tasks."
    let parametersSchema = #"{"type":"object","properties":{}}"#

    private let source: CalendarSource

    init(source: CalendarSource) {
        self.source = source
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // TODO(phase 4)
        .failure("RemindersSkill not yet implemented")
    }
}
