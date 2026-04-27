import Foundation

struct DigestSkill: Skill {
    let name = "generate_digest"
    let description = "Generate a concise morning briefing from the user's calendar, reminders, and recent notes."
    let parametersSchema = #"{"type":"object","properties":{}}"#

    private let digestGenerator: DigestGenerator

    init(digestGenerator: DigestGenerator) {
        self.digestGenerator = digestGenerator
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        do {
            let text = try await digestGenerator.generateText()
            return .success(text)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
