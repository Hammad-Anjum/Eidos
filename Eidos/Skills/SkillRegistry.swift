import Foundation

@MainActor
final class SkillRegistry {
    private(set) var skills: [any Skill]
    var disabledSkillNames: Set<String> = []

    /// Skills that are explicitly enabled by the user / feature flags.
    /// NOTE: this does NOT yet account for runtime permission state —
    /// for that, use `availableSkills()` which is async because it
    /// has to consult each skill's `availability()`.
    var enabledSkills: [any Skill] {
        skills.filter { !disabledSkillNames.contains($0.name) }
    }

    /// Skills that are BOTH enabled AND currently available (permission
    /// granted, feature flag on, hardware supports it). This is what
    /// the `RAGPipeline` should use when building the tool catalogue
    /// for Gemma — exposing skills that will refuse to run is a
    /// confusing user experience.
    ///
    /// Per-skill availability is queried in parallel; on a 14-skill
    /// catalogue this is a few ms total.
    func availableSkills() async -> [any Skill] {
        let candidates = enabledSkills
        // TaskGroup so we don't sequentially await N permission
        // checks. Each skill's availability check is independent.
        return await withTaskGroup(of: (Skill, SkillAvailability).self) { group in
            for skill in candidates {
                group.addTask { (skill, await skill.availability()) }
            }
            var available: [any Skill] = []
            for await (skill, status) in group where status.isAvailable {
                available.append(skill)
            }
            return available
        }
    }

    init(skills: [any Skill]) {
        self.skills = skills
    }

    func dispatch(_ call: ToolCall) async -> SkillResult {
        guard let skill = skills.first(where: { $0.name == call.tool }) else {
            return .failure("Unknown skill: \(call.tool)")
        }
        // Defense in depth: even if the catalogue Gemma saw was filtered
        // to available skills only, a skill's permission could have been
        // revoked between catalogue render and dispatch. Re-check here.
        let availability = await skill.availability()
        if !availability.isAvailable {
            switch availability {
            case .permissionDenied(let message):
                return .failure("\(skill.name) is unavailable: \(message)")
            case .permissionNotDetermined:
                return .failure("\(skill.name) needs permission. Open Settings to grant access, then try again.")
            case .featureFlagDisabled:
                return .failure("\(skill.name) is disabled in this build.")
            case .unsupported(let reason):
                return .failure("\(skill.name) is unsupported: \(reason)")
            case .available:
                break  // unreachable — !isAvailable above
            }
        }
        return await skill.invoke(parameters: call.parameters)
    }
}
