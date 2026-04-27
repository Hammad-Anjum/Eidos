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

    // Character budgets. ~4 chars ≈ 1 token for English.
    //
    // Gemma 4 ships a 128 K context window. We used to cap at 12 000
    // chars (~3 K tokens) for the legacy 8 K-context path; now we can
    // pack ~60 K chars (~15 K tokens) without overflowing, leaving
    // generous room for the user turn + generation + chat template.
    //
    // Toggleable via `EidosFeatureFlags.longContextPackingEnabled` so
    // we can regress quickly if benchmarks show attention spread hurts
    // quality more than extra context helps.
    static let conservativeMaxChars = 12_000
    static let longContextMaxChars = 60_000

    /// Resolves the budget for the current build call. Reads
    /// `EidosFeatureFlags.shared` which is MainActor-isolated, so this
    /// is not a default-argument expression — it's called explicitly
    /// inside `build(...)` which is already on MainActor.
    /// Device-aware budget. Reads `DeviceProfile` so iPhone gets a
    /// tighter cap than iPad/Mac (TPS degrades with context on iPhone
    /// specifically — benchmarks show >30 % throttle past ~10 K tokens
    /// of context on A18/A19 under sustained load). Thermal state
    /// halves the budget further.
    @MainActor
    static func resolvedMaxChars() -> Int {
        DeviceProfile.contextBudgetChars(
            longContextFlag: EidosFeatureFlags.shared.longContextPackingEnabled
        )
    }

    static let memoryShare = 0.6                    // memory gets up to 60% of budget

    let memoryManager: MemoryManager
    let knowledgeRepo: KnowledgeRepository

    // MARK: - Public

    /// Builds the context block for `query`. Also refreshes `lastAccessedAt`
    /// on every memory entry we included, so actively used memories resist
    /// decay.
    func build(query: String, maxChars: Int? = nil) async -> Result {
        let effectiveMax = maxChars ?? Self.resolvedMaxChars()
        let memoryEntries = await gatherMemory()
        // KB topK scales with the packing flag — 5 for conservative,
        // 10 when we have the context to absorb it.
        let kbTopK = EidosFeatureFlags.shared.longContextPackingEnabled ? 10 : 5
        let kbHits = (try? await knowledgeRepo.search(query: query, topK: kbTopK)) ?? []

        let memoryBudget = Int(Double(effectiveMax) * Self.memoryShare)
        let memoryBlock = Self.renderMemory(memoryEntries, maxChars: memoryBudget)
        let kbBudget = effectiveMax - memoryBlock.count
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

    /// Retrieval policy (Phase 8.8 — long-context packing):
    ///
    /// When `longContextPackingEnabled` is on, we exploit Gemma 4's 128 K
    /// window to pack more memory up front rather than filter aggressively.
    /// Tiered by priority + recency:
    ///   • every P1 (core identity — always in context)
    ///   • every `active_priorities` entry
    ///   • up to 30 hottest `topic` entries by `lastAccessedAt` (was 10)
    ///   • capped at 60 total (was 20)
    ///
    /// Rationale from Letta (MemGPT) research: attention spreads, but
    /// more-relevant context measurably beats less-relevant context until
    /// you hit the model's effective attention horizon. Empirically that
    /// horizon for Gemma 4 E2B is ~40-50 K tokens; we stay well below it.
    ///
    /// When the flag is off, we fall back to the conservative behavior
    /// (20 total, 10 topic) so a quality regression is one toggle away.
    private func gatherMemory() async -> [MemoryEntry] {
        let longContext = EidosFeatureFlags.shared.longContextPackingEnabled
        let topicK = longContext ? 30 : 10
        let totalCap = longContext ? 60 : 20

        let index = memoryManager.index
        let p1 = await index.records(priority: .p1)
        let active = await index.records(tier: .activePriorities)
        let hotTopics = await index.topK(topicK, tier: .topic)

        // Merge, dedupe by id, preserve order (P1 → active → topic).
        var seen: Set<UUID> = []
        var ordered: [MemoryIndexRecord] = []
        for record in p1 + active + hotTopics {
            if seen.insert(record.id).inserted { ordered.append(record) }
        }
        let top = ordered.prefix(totalCap)

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
