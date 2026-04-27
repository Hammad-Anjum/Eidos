import Foundation

@MainActor
final class SkillRegistry {
    private(set) var skills: [any Skill]
    var disabledSkillNames: Set<String> = []

    var enabledSkills: [any Skill] {
        skills.filter { !disabledSkillNames.contains($0.name) }
    }

    init(skills: [any Skill]) {
        self.skills = skills
    }

    func dispatch(_ call: ToolCall) async -> SkillResult {
        guard let skill = skills.first(where: { $0.name == call.tool }) else {
            return .failure("Unknown skill: \(call.tool)")
        }
        return await skill.invoke(parameters: call.parameters)
    }
}
