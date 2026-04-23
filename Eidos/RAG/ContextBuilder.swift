import Foundation

/// Assembles the retrieved-context block that gets injected into Gemma's
/// prompt on every turn. Two sources:
///
/// 1. **Memory** — persistent user facts from `MemoryManager`. Always
///    includes all P1 (core identity) + a recency-sorted slice of
///    `active_priorities` and `topic` tiers.
/// 2. **Knowledge base** — hybrid search hits from `KnowledgeRepository`
///    (vector + keyword, merged by RRF — built in Phase 1).
///
/// Output is a single markdown-flavored string, hard-capped at a character
/// budget so we never blow past Gemma 4's ~8K token window.
@MainActor
struct ContextBuilder {

    struct Result: Sendable {
        let text: String                            // ready-for-prompt block
        let memoryEntries: [MemoryEntry]            // what we pulled (for touch / telemetry)
        let kbHits: [KnowledgeRepository.SearchHit]
    }

    // Character budgets. ~4 chars ≈ 1 token for English, so 12 000 chars ≈
    // 3 000 tokens — comfortable for a 2B model with ~8 K context.
    static let defaultMaxChars = 12_000
    static let memoryShare = 0.6                    // memory gets up to 60% of budget

    let memoryManager: MemoryManager
    let knowledgeRepo: KnowledgeRepository

    // MARK: - Public

    /// Builds the context block for `query`. Also refreshes `lastAccessedAt`
    /// on every memory entry we included, so actively used memories resist
    /// decay.
    func build(query: String, maxChars: Int = defaultMaxChars) async -> Result {
        let memoryEntries = await gatherMemory()
        let kbHits = (try? await knowledgeRepo.search(query: query, topK: 5)) ?? []

        let memoryBudget = Int(Double(maxChars) * Self.memoryShare)
        let memoryBlock = Self.renderMemory(memoryEntries, maxChars: memoryBudget)
        let kbBudget = maxChars - memoryBlock.count
        let kbBlock = Self.renderKB(kbHits, maxChars: kbBudget)

        var assembled = ""
        if !memoryBlock.isEmpty { assembled += memoryBlock }
        if !kbBlock.isEmpty {
            if !assembled.isEmpty { assembled += "\n\n" }
            assembled += kbBlock
        }

        // Touch every memory we loaded — keeps them hot under the decay engine.
        for entry in memoryEntries {
            try? await memoryManager.touch(id: entry.id)
        }

        return Result(text: assembled, memoryEntries: memoryEntries, kbHits: kbHits)
    }

    // MARK: - Memory selection

    /// Retrieval policy:
    ///   • every P1 (core identity — always in context)
    ///   • every `active_priorities` entry
    ///   • up to 10 hottest `topic` entries by `lastAccessedAt`
    /// Capped at ~20 entries total to stay within budget.
    private func gatherMemory() async -> [MemoryEntry] {
        let index = memoryManager.index
        let p1 = await index.records(priority: .p1)
        let active = await index.records(tier: .activePriorities)
        let hotTopics = await index.topK(10, tier: .topic)

        // Merge, dedupe by id, preserve order (P1 → active → topic).
        var seen: Set<UUID> = []
        var ordered: [MemoryIndexRecord] = []
        for record in p1 + active + hotTopics {
            if seen.insert(record.id).inserted { ordered.append(record) }
        }
        let top = ordered.prefix(20)

        var entries: [MemoryEntry] = []
        entries.reserveCapacity(top.count)
        for record in top {
            if let entry = try? await memoryManager.load(id: record.id) {
                entries.append(entry)
            }
        }
        return entries
    }

    // MARK: - Rendering

    nonisolated static func renderMemory(_ entries: [MemoryEntry], maxChars: Int) -> String {
        guard !entries.isEmpty, maxChars > 0 else { return "" }
        var out = "## What I remember\n"
        for entry in entries {
            let block = "\n### \(entry.title)\n\(entry.body)\n"
            if out.count + block.count > maxChars { break }
            out += block
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func renderKB(
        _ hits: [KnowledgeRepository.SearchHit],
        maxChars: Int
    ) -> String {
        guard !hits.isEmpty, maxChars > 0 else { return "" }
        var out = "## From your notes\n"
        for hit in hits {
            let block = "\n- \(hit.snippet)\n"
            if out.count + block.count > maxChars { break }
            out += block
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
