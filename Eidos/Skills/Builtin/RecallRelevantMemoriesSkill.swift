import Foundation

/// Chat-side memory recall tool.
///
/// When the user references something they "told you before" / "wrote
/// about" / "mentioned" → Gemma calls this skill with the user's
/// phrasing as the query. The skill runs embedding-based semantic
/// recall against the on-device memory store and returns the top-3
/// hits formatted as bullets for Gemma to compose into prose.
///
/// Design notes:
/// - Recall is **opt-in** per the tool-call pattern. The chat path
///   already injects retrieved memory passively into `## What I
///   remember`, so this skill is for explicit "what did I say about X"
///   queries where the passive recall may have missed the relevant
///   entry.
/// - Score threshold 0.30 mirrors `MemoryRecallService.recall(...)`'s
///   default — permissive enough to catch loose conceptual matches
///   without surfacing noise.
/// - Recall touches `lastAccessedAt` inside the recall service, so the
///   decay engine reflects that the entry is being read.
struct RecallRelevantMemoriesSkill: Skill {

    let name = "recall_relevant_memories"
    let description = "Find past memory entries semantically similar to a query. Call when the user references something they 'told you before' or 'wrote about'."

    let parametersSchema: String = """
    {
      "query": "string — the user's phrasing; what they're asking you to recall"
    }
    """

    let recall: MemoryRecallService

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let query = parameters["query"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty
        else {
            return .failure("Need a query.")
        }

        let hits = await recall.recall(query: query, topK: 3, minScore: 0.30)
        if hits.isEmpty {
            return .success("Nothing recorded about that yet.")
        }

        let lines = hits.prefix(3).map { hit -> String in
            // Body preview: first ~140 chars, one line. Explicit
            // `String(...)` conversion of the Substring so the join
            // below doesn't allocate a Swift Substring-boxed
            // intermediary for each line.
            let preview = String(hit.entry.body
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(140))
            return "- \(hit.entry.title): \(preview)"
        }
        return .success(lines.joined(separator: "\n"))
    }

    func availability() async -> SkillAvailability { .available }
}
