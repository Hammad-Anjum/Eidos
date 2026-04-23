import Foundation

/// Metadata-only projection of a `MemoryEntry`. Carried in the index so
/// queries don't have to read the `.md` body from disk. ~200 bytes each.
struct MemoryIndexRecord: Sendable, Equatable, Identifiable {
    let id: UUID
    var tier: MemoryTier
    var title: String
    var priority: MemoryPriority
    var tags: [String]
    var updatedAt: Date
    var lastAccessedAt: Date

    init(from entry: MemoryEntry) {
        self.id = entry.id
        self.tier = entry.tier
        self.title = entry.title
        self.priority = entry.priority
        self.tags = entry.tags
        self.updatedAt = entry.updatedAt
        self.lastAccessedAt = entry.lastAccessedAt
    }
}

/// In-memory metadata index over the memory store. Populated once at
/// startup by `MemoryManager.rebuildIndex()` and mutated in lock-step
/// with disk writes. Queries are O(N) scans — fine up to ~10k entries.
actor MemoryIndex {

    private var records: [UUID: MemoryIndexRecord] = [:]

    // MARK: - Mutations (called by MemoryManager after successful disk I/O)

    func upsert(_ record: MemoryIndexRecord) {
        records[record.id] = record
    }

    func remove(id: UUID) {
        records.removeValue(forKey: id)
    }

    func clear() {
        records.removeAll(keepingCapacity: true)
    }

    // MARK: - Queries

    var count: Int { records.count }

    var all: [MemoryIndexRecord] {
        Array(records.values)
    }

    func records(tier: MemoryTier) -> [MemoryIndexRecord] {
        records.values.filter { $0.tier == tier }
    }

    func records(withTag tag: String) -> [MemoryIndexRecord] {
        records.values.filter { $0.tags.contains(tag) }
    }

    func records(priority: MemoryPriority) -> [MemoryIndexRecord] {
        records.values.filter { $0.priority == priority }
    }

    /// Most-recently-accessed first, optionally filtered by tier.
    /// Returns at most `n` records. Used by the RAG retriever.
    func topK(_ n: Int, tier: MemoryTier? = nil) -> [MemoryIndexRecord] {
        let pool: [MemoryIndexRecord]
        if let tier {
            pool = records.values.filter { $0.tier == tier }
        } else {
            pool = Array(records.values)
        }
        return Array(
            pool.sorted { $0.lastAccessedAt > $1.lastAccessedAt }.prefix(n)
        )
    }

    /// Entries whose `lastAccessedAt` is older than `days` days ago.
    /// Feeds `MemoryDecayEngine` (built in 3.1c).
    func stale(olderThanDays days: Double, tier: MemoryTier? = nil) -> [MemoryIndexRecord] {
        let cutoff = Date(timeIntervalSinceNow: -days * 86_400)
        let pool = tier.map { t in records.values.filter { $0.tier == t } }
            ?? Array(records.values)
        return pool.filter { $0.lastAccessedAt < cutoff }
    }
}
