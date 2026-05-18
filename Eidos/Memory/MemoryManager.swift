import Foundation

enum MemoryManagerError: Error, LocalizedError {
    case rootDirectoryUnavailable
    case notFound(UUID)

    var errorDescription: String? {
        switch self {
        case .rootDirectoryUnavailable: "Documents directory is unavailable."
        case .notFound(let id): "Memory entry \(id.uuidString) not found."
        }
    }
}

/// Owns the on-disk memory store: `Documents/memory/<tier>/<id>.md`.
/// Reads and writes go through this actor so concurrent callers can't
/// corrupt a file mid-write.
actor MemoryManager {

    private let fm = FileManager.default
    private let rootOverride: URL?
    /// Publicly accessible index actor. `nonisolated` because `MemoryIndex`
    /// is itself an actor and provides its own serialization.
    nonisolated let index: MemoryIndex

    /// Post-save hook fired after every successful `save(_:reindex:)`
    /// whose `reindex` flag is true (the default). `AppContainer`
    /// attaches a hook that pushes the entry into
    /// `MemoryRecallService.indexEntry(...)` so every memory write
    /// becomes findable by semantic recall without each caller
    /// having to remember to index manually.
    ///
    /// Stored as a closure (rather than a typed `MemoryRecallService?`
    /// reference) because `MemoryRecallService` already depends on
    /// `MemoryManager`; a typed reference here would create a
    /// circular layering. The closure is opt-in: tests + early
    /// callers (pre-bootstrap) get the no-hook path automatically.
    private var onSave: (@Sendable (MemoryEntry) async -> Void)?

    /// Pass `rootOverride` in tests to use a throw-away directory.
    init(rootOverride: URL? = nil, index: MemoryIndex = MemoryIndex()) {
        self.rootOverride = rootOverride
        self.index = index
    }

    /// Attach a post-save hook. Called once at app bootstrap by
    /// `AppContainer` after both `MemoryManager` and
    /// `MemoryRecallService` are constructed. Re-attaching overwrites
    /// any prior hook — there's only one current observer slot by
    /// design (no broadcast).
    func attachOnSave(_ hook: @escaping @Sendable (MemoryEntry) async -> Void) {
        self.onSave = hook
    }

    /// Total bytes on disk under `Documents/memory/`. Recursive sum
    /// across every tier directory. O(N entries) so cheap for the
    /// audience scale (<1k memories); fine to call on a view refresh.
    /// Returns 0 if the memory root hasn't been created yet (first
    /// launch, never wrote anything).
    func diskUsageBytes() -> Int64 {
        let root: URL
        do { root = try self.root() } catch { return 0 }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            // Prefer allocated size (matches Finder's "size on disk");
            // fall back to logical size if APFS clones / sparse files
            // make allocated unavailable. Skip directories implicitly
            // — they report 0 here.
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            if let allocated = values?.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let logical = values?.fileSize {
                total += Int64(logical)
            }
        }
        return total
    }

    // MARK: - Startup

    /// Scans every tier on disk and rehydrates the index. Call once at
    /// app bootstrap so downstream callers can query without file I/O.
    func rebuildIndex() async throws {
        await index.clear()
        for tier in MemoryTier.allCases {
            let entries = try list(tier: tier)
            for entry in entries {
                await index.upsert(MemoryIndexRecord(from: entry))
            }
        }
    }

    // MARK: - Root / paths

    /// `<root>/memory/` — created on first access.
    private func root() throws -> URL {
        let base: URL
        if let rootOverride { base = rootOverride }
        else {
            base = try fm.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
        }
        let memoryRoot = base.appendingPathComponent("memory", isDirectory: true)
        if !fm.fileExists(atPath: memoryRoot.path) {
            try fm.createDirectory(at: memoryRoot, withIntermediateDirectories: true)
        }
        return memoryRoot
    }

    private func directory(for tier: MemoryTier) throws -> URL {
        let dir = try root().appendingPathComponent(tier.rawValue, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(for entry: MemoryEntry) throws -> URL {
        try directory(for: entry.tier).appendingPathComponent("\(entry.id.uuidString).md")
    }

    // MARK: - CRUD

    /// Writes `entry` to disk, overwriting any existing file at the same id.
    /// Updates `updatedAt` to now and syncs the index.
    ///
    /// `reindex` controls whether the post-save hook (typically the
    /// `MemoryRecallService.indexEntry` re-embed) fires. Defaults to
    /// true. Callers that mutate only `lastAccessedAt` (eg. `touch`)
    /// pass `false` because the embedding source (title + body) is
    /// unchanged — re-embedding would burn Neural Engine time for no
    /// recall-quality gain.
    @discardableResult
    func save(_ entry: MemoryEntry, reindex: Bool = true) async throws -> MemoryEntry {
        var toWrite = entry
        toWrite.updatedAt = Date()
        let url = try fileURL(for: toWrite)
        let contents = MemoryFrontmatter.render(toWrite)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        await index.upsert(MemoryIndexRecord(from: toWrite))
        if reindex, let hook = onSave {
            await hook(toWrite)
        }
        return toWrite
    }

    /// Loads an entry by id, scanning all tiers. Returns nil if missing.
    func load(id: UUID) throws -> MemoryEntry? {
        for tier in MemoryTier.allCases {
            let candidate = try directory(for: tier)
                .appendingPathComponent("\(id.uuidString).md")
            if fm.fileExists(atPath: candidate.path) {
                let raw = try String(contentsOf: candidate, encoding: .utf8)
                return try MemoryFrontmatter.parse(raw)
            }
        }
        return nil
    }

    /// All entries currently stored in the given tier. Sorted by
    /// `lastAccessedAt` descending (hot first).
    func list(tier: MemoryTier) throws -> [MemoryEntry] {
        let dir = try directory(for: tier)
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        var entries: [MemoryEntry] = []
        entries.reserveCapacity(files.count)
        for url in files {
            let raw = try String(contentsOf: url, encoding: .utf8)
            if let entry = try? MemoryFrontmatter.parse(raw) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }

    /// Deletes an entry by id from whichever tier it lives in and removes
    /// it from the index.
    func delete(id: UUID) async throws {
        for tier in MemoryTier.allCases {
            let candidate = try directory(for: tier)
                .appendingPathComponent("\(id.uuidString).md")
            if fm.fileExists(atPath: candidate.path) {
                try fm.removeItem(at: candidate)
                await index.remove(id: id)
                return
            }
        }
        throw MemoryManagerError.notFound(id)
    }

    /// Updates `lastAccessedAt` to now for the given entry. Used by the
    /// retrieval layer to mark entries as hot and delay decay.
    func touch(id: UUID) async throws {
        guard var entry = try load(id: id) else {
            throw MemoryManagerError.notFound(id)
        }
        entry.lastAccessedAt = Date()
        // Skip the re-embed hook: title + body are unchanged, only
        // `lastAccessedAt` moved. Re-embedding would be wasted work.
        try await save(entry, reindex: false)
    }

    /// Moves an entry to a different tier (e.g. decaying from `topic` to
    /// `archive`). Rewrites the file under the new directory.
    func move(id: UUID, to newTier: MemoryTier) async throws {
        guard let existing = try load(id: id) else {
            throw MemoryManagerError.notFound(id)
        }
        try await delete(id: id)
        var moved = existing
        moved.tier = newTier
        try await save(moved)
    }
}
