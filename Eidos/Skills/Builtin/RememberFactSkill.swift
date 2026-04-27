import Foundation

/// Persists a single durable fact about the user into the memory
/// system (NOT the knowledge base). Used when the user says
/// "remember that…", "I am…", "my wife is…" — facts that should live
/// in the always-loaded context tier, not the retrieved-on-demand KB.
///
/// Contrast with `AddNoteSkill` which writes to the KB (retrieved via
/// search) — long-form content, tagged for later lookup.
///
/// Both tools coexist. Gemma decides which to call based on phrasing:
/// "remember / I am / my X is / my partner" → `remember_fact`
/// "save a note about / write down / here's an article" → `add_note`
struct RememberFactSkill: Skill {
    let name = "remember_fact"
    let description = """
    Store a short durable fact about the user (preferences, relationships, \
    health basics, routines). Use when the user says "remember that I…", \
    "I am / have / prefer / live in…", or states a personal truth Eidos \
    should recall in future sessions. For long-form notes / articles / \
    reference material, use `add_note` instead.
    """
    let parametersSchema = #"""
    {
      "type": "object",
      "properties": {
        "title": {"type": "string", "description": "Short label (< 60 chars)"},
        "body": {"type": "string", "description": "The durable fact"},
        "tier": {"type": "string", "enum": ["core_identity", "active_priorities", "topic"], "description": "Optional. core_identity for always-in-context truths (preferences, relationships). Defaults to topic."},
        "priority": {"type": "integer", "enum": [1,2,3,4,5], "description": "Optional 1-5. 1 is stickiest."},
        "tags": {"type": "array", "items": {"type": "string"}}
      },
      "required": ["title", "body"]
    }
    """#

    private let manager: MemoryManager

    init(manager: MemoryManager) {
        self.manager = manager
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let title = parameters["title"]?.stringValue, !title.isEmpty,
              let body  = parameters["body"]?.stringValue, !body.isEmpty else {
            return .failure("Need both title and body.")
        }
        let tier = (parameters["tier"]?.stringValue).flatMap(MemoryTier.init(rawValue:))
            ?? .topic
        let priority = (parameters["priority"]?.intValue)
            .flatMap(MemoryPriority.init(rawValue:))
            ?? .p3
        let tags = (parameters["tags"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }

        let entry = MemoryEntry(
            tier: tier,
            title: title,
            body: body,
            priority: priority,
            tags: tags
        )

        do {
            _ = try await manager.save(entry)
            return .success("Remembered.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
