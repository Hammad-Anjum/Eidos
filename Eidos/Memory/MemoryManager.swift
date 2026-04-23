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

    /// Pass `rootOverride` in tests to use a throw-away directory.
    init(rootOverride: URL? = nil, index: MemoryIndex = MemoryIndex()) {
        self.rootOverride = rootOverride
        self.index = index
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
    @discardableResult
    func save(_ entry: MemoryEntry) async throws -> MemoryEntry {
        var toWrite = entry
        toWrite.updatedAt = Date()
        let url = try fileURL(for: toWrite)
        let contents = MemoryFrontmatter.render(toWrite)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        await index.upsert(MemoryIndexRecord(from: toWrite))
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
        try await save(entry)
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
