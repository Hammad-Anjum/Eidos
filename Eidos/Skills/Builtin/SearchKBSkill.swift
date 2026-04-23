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
        guard let query = parameters["query"]?.stringValue, !query.isEmpty else {
            return .failure("Missing required parameter: query")
        }
        let topK = parameters["top_k"]?.intValue ?? 5

        do {
            let hits = try await repo.search(query: query, topK: topK)
            if hits.isEmpty {
                return .success("No matches for '\(query)'.")
            }
            let lines = hits.map { "• \($0.snippet)" }
            return .success(lines.joined(separator: "\n"))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
