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
        guard let content = parameters["content"]?.stringValue, !content.isEmpty else {
            return .failure("Missing required parameter: content")
        }
        let tags = (parameters["tags"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }

        do {
            let result = try await repo.insert(
                content: content,
                source: .skillOutput,
                tags: tags
            )
            switch result {
            case .inserted:
                return .success("Noted.")
            case .skippedDuplicate:
                return .success("Already in your notes — skipped.")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
