import Foundation

struct DigestSkill: Skill {
    let name = "generate_digest"
    let description = "Generate a concise morning briefing from the user's calendar and recent notes."
    let parametersSchema = #"{"type":"object","properties":{}}"#

    init() {}

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // TODO(phase 4)
        .failure("DigestSkill not yet implemented")
    }
}
