import Foundation

/// Pulls every mention of a person/topic across memory + KB into a
/// single summary. This is the "viral demo" feature — the moment in
/// a demo where Eidos recalls something only your phone could know.
///
/// Flow:
/// 1. Search memory by title/tag match
/// 2. Search knowledge base via hybrid RRF (vector + keyword)
/// 3. Concatenate hits into a single string; cap at 6 000 chars
/// 4. Optionally feed to Gemma to synthesise a 2-3 sentence answer
///
/// Works offline. Airplane mode. Instant.
@MainActor
final class KnowledgeAggregator {

    struct Finding: Sendable {
        var memoryEntries: [MemoryEntry]
        var kbHits: [KnowledgeRepository.SearchHit]

        var isEmpty: Bool { memoryEntries.isEmpty && kbHits.isEmpty }

        /// Compact markdown block ready for prompt injection.
        func markdown(for topic: String) -> String {
            var out = "## What Eidos knows about \(topic)\n"
            if !memoryEntries.isEmpty {
                out += "\n### From memory\n"
                for entry in memoryEntries {
                    out += "\n**\(entry.title)** — \(entry.body.prefix(280))\n"
                }
            }
            if !kbHits.isEmpty {
                out += "\n### From your notes\n"
                for hit in kbHits { out += "\n- \(hit.snippet)\n" }
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let memoryManager: MemoryManager
    private let knowledgeRepo: KnowledgeRepository

    init(memoryManager: MemoryManager, knowledgeRepo: KnowledgeRepository) {
        self.memoryManager = memoryManager
        self.knowledgeRepo = knowledgeRepo
    }

    // MARK: - Aggregation

    func aggregate(topic: String, topK: Int = 10) async -> Finding {
        let lowered = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return .init(memoryEntries: [], kbHits: []) }

        // Memory: match title, tags, and body
        let index = memoryManager.index
        let candidates = await index.all
        let ids = candidates.filter {
            $0.title.lowercased().contains(lowered)
                || $0.tags.contains(where: { $0.lowercased().contains(lowered) })
        }.prefix(topK).map(\.id)

        var memoryEntries: [MemoryEntry] = []
        for id in ids {
            if let entry = try? await memoryManager.load(id: id) {
                memoryEntries.append(entry)
            }
        }
        // Also scan bodies of any non-title-match entries for the topic.
        if memoryEntries.count < topK {
            for record in candidates where !ids.contains(record.id) {
                if let entry = try? await memoryManager.load(id: record.id),
                   entry.body.lowercased().contains(lowered) {
                    memoryEntries.append(entry)
                    if memoryEntries.count >= topK { break }
                }
            }
        }

        // KB via hybrid search
        let kbHits = (try? await knowledgeRepo.search(query: topic, topK: topK)) ?? []

        return Finding(memoryEntries: memoryEntries, kbHits: kbHits)
    }
}
