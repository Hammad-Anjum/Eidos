import Foundation

struct AddNoteSkill: Skill {
    let name = "add_note"
    let description = "Save a note or piece of information to the knowledge base at the user's request."
    let parametersSchema = #"{"type":"object","properties":{"content":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["content"]}"#

    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // TODO(phase 4)
        .failure("AddNoteSkill not yet implemented")
    }
}
