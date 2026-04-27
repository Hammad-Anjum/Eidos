import Foundation
import SwiftData

// UI-facing knowledge-base façade. MainActor-bound because SwiftData's
// ModelContext (and every @Model object) must be used from the actor that
// owns it. Background embedding work is delegated to
// `KnowledgeBackgroundActor` via a `PersistentIdentifier` handoff — see
// plan.md §A4. @Model objects NEVER cross the actor boundary.
//
// Search is hybrid (plan.md §B9): vector similarity + keyword
// `localizedStandardContains`, merged via Reciprocal Rank Fusion.
@MainActor
final class KnowledgeRepository {

    private let modelContainer: ModelContainer
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let backgroundActor: KnowledgeBackgroundActor
    private let chunker = TextChunker()

    private var modelContext: ModelContext { modelContainer.mainContext }

    init(
        modelContainer: ModelContainer,
        embeddingService: EmbeddingService,
        vectorStore: VectorStore,
        backgroundActor: KnowledgeBackgroundActor
    ) {
        self.modelContainer = modelContainer
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.backgroundActor = backgroundActor
    }

    // MARK: - CRUD

    enum InsertResult: Sendable, Equatable {
        case inserted(PersistentIdentifier)
        case skippedDuplicate
    }

    /// Inserts a new entry. B8: if an entry with the same content hash
    /// already exists, the insert is skipped and the caller is told.
    /// On a successful insert, a background embedding task is kicked off
    /// via `KnowledgeBackgroundActor` and this method returns immediately.
    @discardableResult
    func insert(
        content: String,
        source: EntrySource,
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) async throws -> InsertResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skippedDuplicate }

        let hash = KnowledgeEntry.hash(of: trimmed)
        if try existsEntry(withHash: hash) {
            return .skippedDuplicate
        }

        let entry = KnowledgeEntry(
            content: trimmed,
            source: source,
            tags: tags,
            metadata: metadata
        )
        modelContext.insert(entry)
        try modelContext.save()

        let id = entry.persistentModelID
        let embeddingService = self.embeddingService
        let vectorStore = self.vectorStore
        let chunker = self.chunker
        let backgroundActor = self.backgroundActor
        Task.detached(priority: .utility) {
            await backgroundActor.embedEntry(
                id,
                embeddingService: embeddingService,
                vectorStore: vectorStore,
                chunker: chunker
            )
        }

        return .inserted(id)
    }

    // MARK: - Hybrid search (B9)

    struct SearchHit: Sendable, Equatable {
        let entryID: UUID
        let score: Float
        let snippet: String
    }

    /// Hybrid search: vector similarity + keyword, merged via Reciprocal
    /// Rank Fusion. Falls back to keyword-only if the embedding service
    /// isn't loaded yet (e.g. during first-launch onboarding).
    func search(query: String, topK: Int = 5) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let oversample = max(topK * 2, 10)
        let vecRanking: [UUID]
        if await embeddingService.isLoaded {
            vecRanking = await vectorRanking(query: trimmed, k: oversample)
        } else {
            vecRanking = []
        }
        let kwRanking = keywordRanking(query: trimmed, limit: oversample)

        let fused = Self.reciprocalRankFusion(rankings: [vecRanking, kwRanking])
        let top = Array(fused.prefix(topK))

        return try resolveHits(top, query: trimmed)
    }

    // MARK: - Recent / delete / bootstrap

    func recent(source: EntrySource? = nil, limit: Int = 20) throws -> [KnowledgeEntry] {
        var descriptor = FetchDescriptor<KnowledgeEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let source {
            let raw = source.rawValue
            descriptor.predicate = #Predicate { $0.source == raw }
        }
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func delete(_ entry: KnowledgeEntry) async throws {
        let id = entry.id
        await vectorStore.remove(entryID: id)
        modelContext.delete(entry)
        try modelContext.save()
    }

    /// Loads all EmbeddingRecords into the in-memory VectorStore on launch.
    func loadVectorStoreFromDB() async {
        guard let entries = try? modelContext.fetch(FetchDescriptor<KnowledgeEntry>()) else { return }
        let records: [VectorStore.LoadRecord] = entries.flatMap { entry in
            entry.embeddings.map { rec in
                VectorStore.LoadRecord(
                    embeddingID: rec.id,
                    entryID: entry.id,
                    chunkText: rec.chunkText,
                    vector: rec.floatVector
                )
            }
        }
        await vectorStore.load(records)
    }

    // MARK: - Private helpers

    private func existsEntry(withHash hash: String) throws -> Bool {
        var descriptor = FetchDescriptor<KnowledgeEntry>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func vectorRanking(query: String, k: Int) async -> [UUID] {
        do {
            let vector = try await embeddingService.embed(query)
            let results = await vectorStore.topK(query: vector, k: k)

            // Vector results are per-chunk; collapse to per-entry while
            // preserving the order of first appearance (best chunk wins).
            var seen = Set<UUID>()
            var ordered: [UUID] = []
            for result in results {
                if seen.insert(result.entryID).inserted {
                    ordered.append(result.entryID)
                }
            }
            return ordered
        } catch {
            return []
        }
    }

    private func keywordRanking(query: String, limit: Int) -> [UUID] {
        // `localizedStandardContains` gives us case- and diacritic-insensitive
        // substring match — cheap and good enough until BM25 is justified.
        var descriptor = FetchDescriptor<KnowledgeEntry>(
            predicate: #Predicate { $0.content.localizedStandardContains(query) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.map(\.id)
    }

    private func resolveHits(_ ids: [UUID], query: String) throws -> [SearchHit] {
        guard !ids.isEmpty else { return [] }
        var hits: [SearchHit] = []
        hits.reserveCapacity(ids.count)
        // Rank order matters — use descending RRF score as the hit score.
        for (rank, id) in ids.enumerated() {
            let descriptor = FetchDescriptor<KnowledgeEntry>(
                predicate: #Predicate { $0.id == id }
            )
            guard let entry = try modelContext.fetch(descriptor).first else { continue }
            hits.append(SearchHit(
                entryID: entry.id,
                score: Float(1.0 / Double(rank + 1)),
                snippet: Self.snippet(from: entry.content, around: query)
            ))
        }
        return hits
    }

    // MARK: - Reciprocal Rank Fusion

    /// Canonical RRF: `score(d) = Σ 1 / (k + rank_i(d))` across all
    /// rankings where `d` appears. `k = 60` is the value from the original
    /// paper (Cormack et al. 2009) and is what production hybrid search
    /// systems use by default.
    static func reciprocalRankFusion(
        rankings: [[UUID]],
        k: Double = 60
    ) -> [UUID] {
        var scores: [UUID: Double] = [:]
        for ranking in rankings {
            for (rank, id) in ranking.enumerated() {
                scores[id, default: 0] += 1.0 / (k + Double(rank + 1))
            }
        }
        return scores
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.uuidString < rhs.key.uuidString
            }
            .map(\.key)
    }

    // MARK: - Snippet extraction

    private static func snippet(from content: String, around query: String, window: Int = 120) -> String {
        let lowered = content.lowercased()
        let loweredQuery = query.lowercased()
        if let range = lowered.range(of: loweredQuery) {
            let start = content.index(range.lowerBound, offsetBy: -window, limitedBy: content.startIndex) ?? content.startIndex
            let end = content.index(range.upperBound, offsetBy: window, limitedBy: content.endIndex) ?? content.endIndex
            var slice = String(content[start..<end])
            if start != content.startIndex { slice = "…" + slice }
            if end != content.endIndex { slice += "…" }
            return slice
        }
        // No keyword match — return the head of the content.
        if content.count <= window * 2 { return content }
        return String(content.prefix(window * 2)) + "…"
    }
}
