import Foundation

/// Result of a semantic memory recall query. Carries the matching
/// memory entry plus the cosine-similarity score so the caller can
/// rank or threshold.
struct MemoryRecallHit: Sendable, Identifiable {
    let entry: MemoryEntry
    let score: Float
    var id: UUID { entry.id }
}

/// Embedding-based semantic recall over the user's memory store.
///
/// Wires three pieces that already exist independently:
///   - `EmbeddingService`:   produces L2-normalized sentence vectors
///                           via Apple's `NLContextualEmbedding`
///   - `VectorStore`:        cosine-similarity dot-product index
///                           (vDSP-accelerated, in-memory)
///   - `MemoryManager`:      the on-disk MD store + index
///
/// Before this service, memory retrieval was keyword-only — the
/// `ContextBuilder` could only find memories whose title contained
/// the user's literal query terms. "What did I tell you about thai
/// food?" matched only memories with the word "thai" in the title.
/// This service is the first path that finds memories by MEANING,
/// turning the second-brain demo from "okay" to "memorable".
///
/// Index population is opportunistic:
///   - `indexEntry(_:)` is called by `MemoryCrystallizer` after a
///     new fact is written so the next chat turn can recall it.
///   - `rebuildIndex()` walks the entire disk store at app boot for
///     any entries that pre-date this service.
actor MemoryRecallService {

    private let embedding: EmbeddingService
    private let vectorStore: VectorStore
    private let manager: MemoryManager

    /// Embedding IDs we've already indexed, to dedupe rebuilds.
    private var indexedEntryIDs: Set<UUID> = []

    init(
        embedding: EmbeddingService,
        vectorStore: VectorStore,
        manager: MemoryManager
    ) {
        self.embedding = embedding
        self.vectorStore = vectorStore
        self.manager = manager
    }

    // MARK: - Indexing

    /// Computes the embedding for a memory entry and inserts it into
    /// the vector store. Idempotent — re-indexing the same entry
    /// replaces its prior vector. Safe to call from
    /// `MemoryCrystallizer` immediately after persisting.
    ///
    /// Failure modes are logged, not thrown. Memory recall improving
    /// over time is a soft promise; one entry failing to index isn't
    /// worth blocking the chat path.
    func indexEntry(_ entry: MemoryEntry) async {
        // Embedding source: title + body, capped. Title is weighted
        // implicitly by being first — embedding mean-pool gives equal
        // weight per token so longer bodies dilute the title signal,
        // but title is usually the most queryable string.
        let source = entry.title + "\n\n" + entry.body
        do {
            let vector = try await embedding.embed(source)
            // Replace any prior vector for this entry id.
            await vectorStore.remove(entryID: entry.id)
            await vectorStore.add(
                embeddingID: UUID(),
                entryID: entry.id,
                chunkText: entry.title,   // displayed in retrieval results
                vector: vector
            )
            indexedEntryIDs.insert(entry.id)
            EidosLogger.shared.log(.info, category: .memory,
                event: "memory.recall.indexed",
                payload: ["entry_id": entry.id.uuidString])
        } catch {
            EidosLogger.shared.error(.memory,
                event: "memory.recall.index-failed",
                error: error, failure: .ragEmbed)
        }
    }

    /// One-shot index bootstrap. Walks every tier and indexes every
    /// entry not already in `indexedEntryIDs`. Cheap on first run
    /// (typical user has < 200 memories), no-op on subsequent calls.
    ///
    /// Early-exits without iterating when the embedding service hasn't
    /// loaded its NLContextualEmbedding assets. Without this guard,
    /// every existing memory entry would call into `indexEntry` and
    /// the embed() call would throw `EmbeddingError.notLoaded`, logging
    /// one error per entry. On simulator the embedding service NEVER
    /// loads (asset download blocked at `/var/db/com.apple.naturallanguaged`),
    /// so every launch would emit ~N error lines for no functional
    /// effect. On real device the rebuild runs later when the embedding
    /// service finishes loading.
    func rebuildIndex() async {
        guard await embedding.isLoaded else {
            EidosLogger.shared.log(.info, category: .memory,
                event: "memory.recall.rebuild.skipped",
                message: "Embedding service not loaded yet; will retry on next save or app launch.")
            return
        }

        EidosLogger.shared.log(.info, category: .memory,
            event: "memory.recall.rebuild.start")
        var indexed = 0
        for tier in MemoryTier.allCases {
            let entries = (try? await manager.list(tier: tier)) ?? []
            for entry in entries where !indexedEntryIDs.contains(entry.id) {
                await indexEntry(entry)
                indexed += 1
            }
        }
        EidosLogger.shared.log(.info, category: .memory,
            event: "memory.recall.rebuild.done",
            payload: ["newly_indexed": indexed])
    }

    /// Removes an entry from the recall index. Called by
    /// `MemoryDecayEngine` when a memory is evicted, and by
    /// `MemoryManager.delete` if we wire it through.
    func forget(entryID: UUID) async {
        await vectorStore.remove(entryID: entryID)
        indexedEntryIDs.remove(entryID)
    }

    // MARK: - Conflict detection

    /// Returns memories whose embedding is highly similar to
    /// `candidate` AND whose priority is high enough that an
    /// inversion would matter. Used by the crystallizer to flag
    /// candidates like:
    ///   existing: "User is vegetarian." (P2)
    ///   new:      "User had chicken last night." (incoming P3)
    /// for explicit user reconciliation rather than silent stack-up.
    ///
    /// "High similarity" is cosine >= 0.55 — empirically this
    /// catches conceptually-related memories ("food preferences")
    /// without flagging every loosely-similar topic. Caller decides
    /// whether the candidate is contradictory; this just surfaces
    /// the candidates worth asking about.
    func similarHighPriority(
        to candidate: String,
        threshold: Float = 0.55,
        maxResults: Int = 5
    ) async -> [MemoryRecallHit] {
        guard !candidate.isEmpty else { return [] }
        let vector: [Float]
        do {
            vector = try await embedding.embed(candidate)
        } catch {
            return []
        }
        let raw = await vectorStore.topK(query: vector, k: maxResults * 2)
        var hits: [MemoryRecallHit] = []
        for result in raw where result.score >= threshold {
            guard let entry = try? await manager.load(id: result.entryID) else { continue }
            // Only flag against P1/P2 entries — those are the "core
            // identity" / "active priorities" tier where contradictions
            // matter. Topic / archive memories drift naturally and
            // don't need user-confirmed reconciliation.
            if entry.priority == .p1 || entry.priority == .p2 {
                hits.append(MemoryRecallHit(entry: entry, score: result.score))
                if hits.count >= maxResults { break }
            }
        }
        return hits
    }

    // MARK: - Recall

    /// Returns up to `topK` memories ordered by semantic similarity to
    /// `query`. Score threshold of 0.30 (cosine) screens out obviously
    /// unrelated hits — Apple's NLContextualEmbedding scores cluster
    /// 0.20-0.95 for related-vs-unrelated content, and 0.30 is a
    /// permissive lower bound that catches loose conceptual matches
    /// without surfacing pure noise.
    func recall(
        query: String,
        topK: Int = 5,
        minScore: Float = 0.30
    ) async -> [MemoryRecallHit] {
        guard !query.isEmpty else { return [] }
        let vector: [Float]
        do {
            vector = try await embedding.embed(query)
        } catch {
            EidosLogger.shared.error(.memory,
                event: "memory.recall.query-embed-failed",
                error: error, failure: .ragEmbed)
            return []
        }

        // Pull more than k from the vector store so we can filter out
        // archive-tier hits and apply the score threshold without
        // running short.
        let raw = await vectorStore.topK(query: vector, k: topK * 2)
        var hits: [MemoryRecallHit] = []
        for result in raw where result.score >= minScore {
            // Resolve UUID -> full MemoryEntry for the caller.
            guard let entry = try? await manager.load(id: result.entryID) else {
                continue
            }
            // Skip archived entries unless caller specifically wants them.
            if entry.tier == .archive { continue }
            // Touch lastAccessedAt so the decay engine treats this
            // recall as activity. Failures are logged, not surfaced —
            // a stale timestamp shouldn't block returning the hit.
            do {
                try await manager.touch(id: entry.id)
            } catch {
                EidosLogger.shared.log(.warn, category: .memory,
                    event: "memory.recall.touch.failed",
                    message: error.localizedDescription,
                    payload: ["entry_id": entry.id.uuidString])
            }
            hits.append(MemoryRecallHit(entry: entry, score: result.score))
            if hits.count >= topK { break }
        }
        EidosLogger.shared.metric(.memory, event: "memory.recall.queried", values: [
            "query_chars": query.count,
            "hits": hits.count,
            "raw_candidates": raw.count,
            "min_score": Double(minScore),
        ])
        return hits
    }
}
