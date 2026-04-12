import Foundation
import Accelerate

// In-memory vector index. Loaded from SwiftData on launch. All searches use
// Accelerate vDSP for dot-product on L2-normalised vectors (= cosine similarity).
actor VectorStore {

    struct Entry: Sendable {
        let embeddingID: UUID
        let entryID: UUID
        let chunkText: String
        let vector: [Float]
    }

    struct LoadRecord: Sendable {
        let embeddingID: UUID
        let entryID: UUID
        let chunkText: String
        let vector: [Float]
    }

    private var entries: [Entry] = []

    init() {}

    func load(_ records: [LoadRecord]) {
        entries = records.map { r in
            Entry(
                embeddingID: r.embeddingID,
                entryID: r.entryID,
                chunkText: r.chunkText,
                vector: r.vector
            )
        }
    }

    func add(embeddingID: UUID, entryID: UUID, chunkText: String, vector: [Float]) {
        entries.append(Entry(
            embeddingID: embeddingID,
            entryID: entryID,
            chunkText: chunkText,
            vector: vector
        ))
    }

    func remove(entryID: UUID) {
        entries.removeAll { $0.entryID == entryID }
    }

    var count: Int { entries.count }

    struct SearchResult: Sendable {
        let entryID: UUID
        let score: Float
        let chunkText: String
    }

    func topK(query: [Float], k: Int) -> [SearchResult] {
        guard !entries.isEmpty else { return [] }
        let dim = vDSP_Length(query.count)
        let scored: [(Entry, Float)] = entries.map { entry in
            var dot: Float = 0
            vDSP_dotpr(query, 1, entry.vector, 1, &dot, dim)
            return (entry, dot)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(k).map {
            SearchResult(entryID: $0.0.entryID, score: $0.1, chunkText: $0.0.chunkText)
        }
    }
}
