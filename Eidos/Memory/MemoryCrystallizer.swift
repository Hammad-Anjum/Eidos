import Foundation

enum MemoryCrystallizerError: Error, LocalizedError {
    case emptyConversation
    case modelReturnedNoMemories
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyConversation: "Nothing to crystallize — conversation is empty."
        case .modelReturnedNoMemories: "Model produced no memories for this session."
        case .malformedResponse(let s): "Crystallizer response was malformed: \(s)"
        }
    }
}

/// End-of-session digestion. Feeds the conversation to Gemma with an
/// extraction prompt and stores the model's distilled notes as
/// `MemoryEntry` records.
///
/// Runs asynchronously when a chat ends — should be cheap enough (a few
/// hundred output tokens) to run on a short timeout.
actor MemoryCrystallizer {

    private let gemma: GemmaSession
    private let manager: MemoryManager

    init(gemma: GemmaSession, manager: MemoryManager) {
        self.gemma = gemma
        self.manager = manager
    }

    /// Extracts memorable facts from a conversation and persists them.
    /// Returns the list of newly-created entries.
    @discardableResult
    func crystallize(
        conversation: [(role: String, content: String)],
        defaultTier: MemoryTier = .topic,
        defaultPriority: MemoryPriority = .p3
    ) async throws -> [MemoryEntry] {
        guard !conversation.isEmpty else { throw MemoryCrystallizerError.emptyConversation }

        let messages = PromptTemplates.crystallization(conversation: conversation)
        let stream = try await gemma.generate(messages: messages)

        var raw = ""
        for try await chunk in stream { raw += chunk }

        let items = try parse(raw)
        guard !items.isEmpty else { throw MemoryCrystallizerError.modelReturnedNoMemories }

        var saved: [MemoryEntry] = []
        saved.reserveCapacity(items.count)
        for item in items {
            let entry = MemoryEntry(
                tier: item.tier ?? defaultTier,
                title: item.title,
                body: item.body,
                priority: item.priority ?? defaultPriority,
                tags: item.tags
            )
            let stored = try await manager.save(entry)
            saved.append(stored)
        }
        return saved
    }

    // MARK: - Parsing

    /// One unit produced by the model. Tier/priority are optional — the
    /// caller provides defaults when the model doesn't specify.
    struct CrystallizedItem: Sendable {
        var title: String
        var body: String
        var tags: [String]
        var tier: MemoryTier?
        var priority: MemoryPriority?
    }

    /// Extracts the first balanced `[...]` JSON array from `raw` (the model
    /// often wraps its output in prose) and decodes it.
    func parse(_ raw: String) throws -> [CrystallizedItem] {
        guard let arrayString = extractJSONArray(raw) else {
            throw MemoryCrystallizerError.malformedResponse("no JSON array found")
        }
        guard let data = arrayString.data(using: .utf8) else {
            throw MemoryCrystallizerError.malformedResponse("non-UTF8")
        }
        guard let any = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MemoryCrystallizerError.malformedResponse("not an array of objects")
        }

        return any.compactMap { dict in
            guard let title = dict["title"] as? String, !title.isEmpty,
                  let body = dict["body"] as? String, !body.isEmpty else {
                return nil
            }
            let tags = dict["tags"] as? [String] ?? []
            let tier = (dict["tier"] as? String).flatMap(MemoryTier.init(rawValue:))
            let priority = (dict["priority"] as? Int).flatMap(MemoryPriority.init(rawValue:))
            return CrystallizedItem(
                title: title, body: body, tags: tags,
                tier: tier, priority: priority
            )
        }
    }

    /// Finds the first top-level `[` … `]` JSON array in `raw`.
    /// Scans with a bracket counter; respects string literals so `[` /
    /// `]` inside strings don't confuse it.
    private func extractJSONArray(_ raw: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escape = false
        for i in raw.indices {
            let c = raw[i]
            if escape { escape = false; continue }
            if inString {
                if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "[":
                if depth == 0 { start = i }
                depth += 1
            case "]":
                depth -= 1
                if depth == 0, let s = start {
                    return String(raw[s...i])
                }
            default: break
            }
        }
        return nil
    }
}
