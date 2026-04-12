import Foundation

struct SearchKBSkill: Skill {
    let name = "search_knowledge_base"
    let description = "Search personal notes, imported messages, and stored information. Use for questions about past events, preferences, or stored data."
    let parametersSchema = #"{"type":"object","properties":{"query":{"type":"string"},"top_k":{"type":"integer","default":5}},"required":["query"]}"#

    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // TODO(phase 4)
        .failure("SearchKBSkill not yet implemented")
    }
}
