import Foundation
import SwiftData

// Background-embedding worker. Owns its own ModelContext spun from the
// shared ModelContainer so it can fetch/write @Model objects without
// crossing actor boundaries — see plan.md §A4.
//
// The @ModelActor macro synthesises:
//   - `init(modelContainer: ModelContainer)`
//   - `nonisolated let modelContainer: ModelContainer`
//   - `let modelContext: ModelContext` (bound to this actor)
//   - `subscript<T>(id: PersistentIdentifier, as: T.Type) -> T?`
//
// Callers hand us a `PersistentIdentifier` (which is Sendable); we
// re-fetch the model locally and work on it here. @Model objects never
// cross the actor boundary.
@ModelActor
actor KnowledgeBackgroundActor {

    /// Chunks, embeds, and persists an entry whose row already exists in
    /// the store. The caller on the main actor passes the entry's
    /// `PersistentIdentifier`; we fetch, work, and save entirely inside
    /// this actor's context.
    ///
    /// Thermal guard (B11): if the device is in `.critical` thermal state
    /// we bail out early. The entry will be picked up on the next
    /// successful insert or by a future re-index pass.
    func embedEntry(
        _ id: PersistentIdentifier,
        embeddingService: EmbeddingService,
        vectorStore: VectorStore,
        chunker: TextChunker
    ) async {
        if ProcessInfo.processInfo.thermalState == .critical {
            return
        }

        guard let entry = self[id, as: KnowledgeEntry.self] else { return }

        let chunks = chunker.chunk(entry.content)
        guard !chunks.isEmpty else { return }

        for (index, chunk) in chunks.enumerated() {
            // Check thermal state between chunks so a long document
            // doesn't cook the device.
            if ProcessInfo.processInfo.thermalState == .critical {
                break
            }

            let vector: [Float]
            do {
                vector = try await embeddingService.embed(chunk)
            } catch {
                // Skip this chunk; embedding service will surface the
                // problem through its own logging / UI channel.
                continue
            }

            let record = EmbeddingRecord(
                chunkIndex: index,
                chunkText: chunk,
                vector: vector
            )
            entry.embeddings.append(record)

            await vectorStore.add(
                embeddingID: record.id,
                entryID: entry.id,
                chunkText: chunk,
                vector: vector
            )
        }

        do {
            try modelContext.save()
        } catch {
            // Failing to save is not fatal — the next insert on the main
            // actor will trigger another save attempt. Real logging lands
            // in Phase 6 alongside the rest of the telemetry policy.
        }
    }
}
