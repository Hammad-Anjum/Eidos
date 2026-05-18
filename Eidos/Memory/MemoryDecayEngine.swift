import Foundation

/// Summary of what a decay pass did. Surfaced so the UI (or tests) can
/// show the user what happened.
struct DecayReport: Sendable, Equatable, Codable {
    var promoted: [UUID] = []     // priority got stickier (newer, more-used)
    var demoted: [UUID] = []      // priority got less sticky
    var archived: [UUID] = []     // moved to .archive tier
    var evicted: [UUID] = []      // deleted (P5 + way stale)
    /// Pinned entries we examined and skipped because the user
    /// explicitly asked us to keep them. Reported (not silently
    /// skipped) so the Diagnostics surface can show "12 pinned
    /// memories were exempted from this pass."
    var skippedPinned: [UUID] = []
    /// When this pass ran. Stamped at the end of `runOnce` so the
    /// Diagnostics surface can show "last decay pass: 14h ago".
    var ranAt: Date = .init()

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

    /// Runs one pass over the index and applies decay rules. Pinned
    /// entries are exempt from priority demotion, archival, and
    /// eviction — they only get tracked in `report.skippedPinned`.
    @discardableResult
    func runOnce(now: Date = Date()) async throws -> DecayReport {
        var report = DecayReport()

        let records = await manager.index.all
        for record in records {
            let inactiveSeconds = now.timeIntervalSince(record.lastAccessedAt)
            let inactiveDays = inactiveSeconds / 86_400
            guard inactiveDays >= record.priority.staleAfterDays else { continue }

            // Pinned entries: user has said "keep this forever".
            // Track that we saw it (so Diagnostics can show "N pinned
            // memories were exempted from this pass") but never modify.
            if record.pinned {
                report.skippedPinned.append(record.id)
                continue
            }

            // Per-record do/catch so one broken entry doesn't kill the
            // whole pass. The previous shape let any throw out of
            // `demote` / `archive` / `delete` propagate up through
            // `runOnce`, aborting the remaining records mid-loop —
            // worst case, a single corrupt markdown file would stall
            // decay indefinitely until the user found and fixed it.
            do {
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
            } catch {
                EidosLogger.shared.log(.warn, category: .memory,
                    event: "memory.decay.record.failed",
                    message: error.localizedDescription,
                    payload: [
                        "entry_id": record.id.uuidString,
                        "priority": record.priority.rawValue,
                    ]
                )
                // Continue with remaining records.
            }
        }

        report.ranAt = now
        // Persist the latest report so Diagnostics + Settings can
        // show "last pass: <relative>" without re-running anything.
        Self.persistLatest(report)
        EidosLogger.shared.metric(.memory, event: "memory.decay.ran", values: [
            "demoted": report.demoted.count,
            "archived": report.archived.count,
            "evicted": report.evicted.count,
            "skipped_pinned": report.skippedPinned.count,
        ])

        return report
    }

    // MARK: - Latest-report persistence

    /// `<AppSupport>/eidos/memory/decay_latest.json`. Tiny — a few
    /// hundred bytes — and overwritten on every run. Surfaced by
    /// Diagnostics so the user can see the most recent decay summary
    /// without re-running.
    private static func latestReportURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("eidos/memory", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("decay_latest.json")
    }

    private static func persistLatest(_ report: DecayReport) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            let url = try latestReportURL()
            try data.write(to: url, options: .atomic)
        } catch {
            // Decay must not crash the app if the report can't be
            // persisted; just log and move on.
            EidosLogger.shared.error(.memory,
                event: "memory.decay.persist-failed",
                error: error, failure: .memoryWrite)
        }
    }

    /// Loads the most recent decay report from disk. Returns nil if no
    /// pass has run yet on this device.
    static func loadLatestReport() -> DecayReport? {
        do {
            let url = try latestReportURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DecayReport.self, from: data)
        } catch {
            return nil
        }
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
    ///
    /// The tier move and the priority demotion are kept on either side
    /// of a single `manager.save` so the on-disk state is never seen
    /// as "archived but still P4". `manager.move` updates the markdown
    /// location; the subsequent save persists the priority change. If
    /// the process is killed between the two, the next decay pass
    /// re-enters this method (the early `if record.tier != .archive`
    /// no-ops the move) and finishes the priority bump — idempotent.
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
