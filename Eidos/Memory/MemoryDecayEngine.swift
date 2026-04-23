import Foundation

/// Summary of what a decay pass did. Surfaced so the UI (or tests) can
/// show the user what happened.
struct DecayReport: Sendable, Equatable {
    var promoted: [UUID] = []     // priority got stickier (newer, more-used)
    var demoted: [UUID] = []      // priority got less sticky
    var archived: [UUID] = []     // moved to .archive tier
    var evicted: [UUID] = []      // deleted (P5 + way stale)

    var isNoop: Bool {
        promoted.isEmpty && demoted.isEmpty && archived.isEmpty && evicted.isEmpty
    }
}

/// Walks the memory store and applies the retention policy:
///
/// | priority | stale after |  action when stale  |
/// | :------: | :---------: | :-----------------: |
/// |    P1    |     ∞       | —                   |
/// |    P2    |   14 d      | demote to P3        |
/// |    P3    |   60 d      | demote to P4        |
/// |    P4    |  180 d      | move to .archive    |
/// |    P5    |  365 d      | evict (delete)      |
///
/// Intended to run once a day. Can be invoked manually from Settings too.
actor MemoryDecayEngine {

    private let manager: MemoryManager

    init(manager: MemoryManager) {
        self.manager = manager
    }

    /// Runs one pass over the index and applies decay rules.
    @discardableResult
    func runOnce(now: Date = Date()) async throws -> DecayReport {
        var report = DecayReport()

        let records = await manager.index.all
        for record in records {
            let inactiveSeconds = now.timeIntervalSince(record.lastAccessedAt)
            let inactiveDays = inactiveSeconds / 86_400
            guard inactiveDays >= record.priority.staleAfterDays else { continue }

            switch record.priority {
            case .p1:
                continue  // never touched
            case .p2:
                try await demote(record, to: .p3)
                report.demoted.append(record.id)
            case .p3:
                try await demote(record, to: .p4)
                report.demoted.append(record.id)
            case .p4:
                try await archive(record)
                report.archived.append(record.id)
            case .p5:
                try await manager.delete(id: record.id)
                report.evicted.append(record.id)
            }
        }

        return report
    }

    // MARK: - Helpers

    private func demote(_ record: MemoryIndexRecord, to newPriority: MemoryPriority) async throws {
        guard var entry = try await manager.load(id: record.id) else { return }
        entry.priority = newPriority
        try await manager.save(entry)
    }

    /// Moves a record to `.archive` and demotes its priority one step.
    /// Archived entries don't participate in hot-path retrieval but are
    /// still searchable via the knowledge base.
    private func archive(_ record: MemoryIndexRecord) async throws {
        if record.tier != .archive {
            try await manager.move(id: record.id, to: .archive)
        }
        // After the move, bump priority to P5 so it will be evicted next pass.
        guard var entry = try await manager.load(id: record.id) else { return }
        entry.priority = .p5
        try await manager.save(entry)
    }
}
