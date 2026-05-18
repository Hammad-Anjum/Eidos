import Foundation

/// Deterministic builder for the user's exportable weekly summary.
///
/// Walks `MemoryIndexRecord` metadata (cheap, in-memory) for everything
/// except body-double sessions — those need the on-disk body to surface
/// the per-session duration. Renders plain markdown so the share-sheet
/// destination (Mail, Messages, Files, Print) gets a document a human
/// can read without rendering, and so the recipient can copy passages
/// out if they want.
///
/// **Pure function, no Gemma.** Documents that may end up in a
/// clinician's intake folder should never contain LLM-narrated
/// patterns — too much hallucination risk, too little upside. The
/// renderer mirrors the user's data 1:1 and footers it with a
/// neutral disclaimer so the recipient has no ambiguity about what
/// they're looking at.
///
/// Tonal rules (carried from `CLAUDE.md`):
/// - Never uses "Doctor / Therapist / Coach" anywhere.
/// - Never makes diagnostic claims.
/// - Never moralizes ("should", "ought", "really need to").
/// - Empty-week output is gentle, never accusatory ("Quiet week.")
enum WeeklySummaryBuilder {

    /// Everything the renderer needs. Collected by the caller so the
    /// builder itself stays pure — easier to test, easier to reason
    /// about, no actor isolation in the markdown logic.
    struct Inputs: Sendable {
        let records: [MemoryIndexRecord]
        /// Full entries for body-double sessions (needed for duration
        /// — `MemoryIndexRecord` carries metadata only). Other sections
        /// don't need bodies and stay metadata-only by design (less
        /// data in the shared document = better privacy posture).
        let bodyDoubleEntries: [MemoryEntry]
        let memoryCount: Int
        let diskBytes: Int64
        let weekEnding: Date
        let egressArmedAt: Date?
        let appVersion: String
        let appBuild: String
    }

    /// Returns 7 days worth of weekly summary markdown. Section
    /// headings only appear when their section has data — an empty
    /// week renders a single "Quiet week" line rather than a parade
    /// of zeros (which would feel like a report card).
    static func build(inputs: Inputs) -> String {
        let (weekStart, weekEnd) = weekBounds(endingAt: inputs.weekEnding)
        let weekRecords = inputs.records.filter { rec in
            // Anything updated *or* touched in the window counts.
            // `updatedAt` covers fresh creates (journal, scene,
            // body-double, energy); `lastAccessedAt` covers
            // priorities that got picked by What Now via `touch()`.
            (rec.updatedAt >= weekStart && rec.updatedAt <= weekEnd) ||
            (rec.lastAccessedAt >= weekStart && rec.lastAccessedAt <= weekEnd)
        }

        var lines: [String] = []
        lines.append("# Eidos — Weekly summary")
        lines.append("**\(formatRange(weekStart, weekEnd))**")
        lines.append("")
        lines.append("> Generated on-device by Eidos. Self-reported data. Not a diagnostic record.")
        lines.append("")
        lines.append("---")
        lines.append("")

        let energySection      = renderEnergy(weekRecords)
        let bodyDoubleSection  = renderBodyDouble(weekRecords, bodies: inputs.bodyDoubleEntries, in: weekStart...weekEnd)
        let sceneSection       = renderScenes(weekRecords)
        let journalSection     = renderJournals(weekRecords)
        let tasksPickedSection = renderTasksPicked(weekRecords, in: weekStart...weekEnd)
        let prioritiesSection  = renderCurrentPriorities(inputs.records)

        let sections = [
            energySection,
            bodyDoubleSection,
            sceneSection,
            journalSection,
            tasksPickedSection,
            prioritiesSection,
        ].compactMap { $0 }

        if sections.allSatisfy({ $0.isEmpty }) || sections.isEmpty {
            lines.append("## Quiet week")
            lines.append("")
            lines.append("No new entries between \(formatDate(weekStart)) and \(formatDate(weekEnd)).")
            lines.append("")
        } else {
            for section in sections where !section.isEmpty {
                lines.append(section)
                lines.append("")
            }
        }

        lines.append("---")
        lines.append("")
        lines.append(footer(inputs: inputs))
        return lines.joined(separator: "\n")
    }

    /// Writes the markdown to a fresh file under `tmp/` named after
    /// the week end-date so multiple weekly exports don't collide.
    /// Returns the URL ready to hand to the share sheet.
    static func writeToTempFile(_ markdown: String, weekEnding: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "eidos-weekly-\(formatter.string(from: weekEnding)).md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Section renderers

    private static func renderEnergy(_ records: [MemoryIndexRecord]) -> String {
        let entries = records.filter { $0.tags.contains("energy") }
        guard !entries.isEmpty else { return "" }

        // Each energy entry's title is `"Energy → N (label)"`. Parse
        // the integer back out so we can bucket by level without
        // re-reading bodies from disk.
        var counts: [Int: Int] = [:]
        for entry in entries {
            if let level = parseEnergyLevel(from: entry.title) {
                counts[level, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return "" }

        let labels = [0: "burnout", 1: "low", 2: "okay", 3: "good", 4: "high"]
        let mostCommon = counts.max(by: { $0.value < $1.value })

        var lines: [String] = ["## Energy"]
        if let most = mostCommon, let label = labels[most.key] {
            lines.append("Most common: **\(label)** (\(most.value) entries)")
        }
        lines.append("")
        for level in 0...4 {
            let count = counts[level] ?? 0
            if count > 0 {
                lines.append("- \(labels[level] ?? "?"): \(count)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderBodyDouble(
        _ records: [MemoryIndexRecord],
        bodies: [MemoryEntry],
        in range: ClosedRange<Date>
    ) -> String {
        let entries = records.filter { $0.tags.contains("body-double") }
        guard !entries.isEmpty else { return "" }

        // Cross-reference index records with full entries to pull the
        // duration out of each body. `bodies` may be a superset (all
        // body-double entries ever) — filter to the records we care
        // about by id.
        let recordIDs = Set(entries.map(\.id))
        let bodiesInWeek = bodies.filter { recordIDs.contains($0.id) }

        let total = bodiesInWeek.reduce(0) { acc, entry in
            acc + (parseDurationMinutes(from: entry.body) ?? 0)
        }

        var lines: [String] = ["## Body-double sessions"]
        lines.append("**\(entries.count) \(pluralize("session", entries.count)), \(total) min total.**")
        lines.append("")
        // Sort most-recent first so a reader scans newest activity at top.
        let sorted = entries.sorted { $0.updatedAt > $1.updatedAt }
        for record in sorted {
            let body = bodiesInWeek.first(where: { $0.id == record.id })
            let minutes = body.flatMap { parseDurationMinutes(from: $0.body) } ?? 0
            let dateString = formatDate(record.updatedAt)
            let title = stripPrefix(record.title, prefix: "Sat with — ")
            if minutes > 0 {
                lines.append("- \(title) — \(minutes) min  · \(dateString)")
            } else {
                lines.append("- \(title)  · \(dateString)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderScenes(_ records: [MemoryIndexRecord]) -> String {
        let entries = records.filter {
            $0.tags.contains("scene") || $0.tags.contains("look-mode")
        }
        guard !entries.isEmpty else { return "" }

        var lines: [String] = ["## Scene break-downs"]
        lines.append("**\(entries.count) \(pluralize("scene", entries.count)).**")
        lines.append("")
        let sorted = entries.sorted { $0.updatedAt > $1.updatedAt }
        for record in sorted {
            let title = stripPrefix(record.title, prefix: "Scene breakdown — ")
            lines.append("- \(title)  · \(formatDate(record.updatedAt))")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderJournals(_ records: [MemoryIndexRecord]) -> String {
        let entries = records.filter { $0.tags.contains("journal") }
        guard !entries.isEmpty else { return "" }

        var lines: [String] = ["## Journal entries"]
        lines.append("**\(entries.count) \(pluralize("entry", entries.count, plural: "entries")).**")
        lines.append("")
        let sorted = entries.sorted { $0.updatedAt > $1.updatedAt }
        for record in sorted {
            lines.append("- \(record.title)  · \(formatDate(record.updatedAt))")
        }
        lines.append("")
        lines.append("_Bodies omitted by default. Open an entry in the Memory tab to copy details manually if you want to include them._")
        return lines.joined(separator: "\n")
    }

    private static func renderTasksPicked(
        _ records: [MemoryIndexRecord],
        in range: ClosedRange<Date>
    ) -> String {
        // "Picked" semantics mirror the Today section: an
        // `activePriorities` record whose `lastAccessedAt` was touched
        // *after* the entry was last updated. `PickNextTaskSkill.touch`
        // bumps only `lastAccessedAt`, so the inequality is the
        // signal that the user actually picked the priority via What
        // Now (vs merely creating or editing it this week).
        let picks = records.filter {
            $0.tier == .activePriorities &&
            range.contains($0.lastAccessedAt) &&
            $0.lastAccessedAt > $0.updatedAt
        }
        guard !picks.isEmpty else { return "" }

        var lines: [String] = ["## Tasks picked via What Now"]
        lines.append("**\(picks.count) \(pluralize("pick", picks.count)).**")
        lines.append("")
        let sorted = picks.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        for record in sorted {
            lines.append("- \(record.title)  · \(formatDate(record.lastAccessedAt))")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderCurrentPriorities(_ allRecords: [MemoryIndexRecord]) -> String {
        let priorities = allRecords
            .filter { $0.tier == .activePriorities }
            .sorted { $0.priority.rawValue < $1.priority.rawValue }
        guard !priorities.isEmpty else { return "" }

        var lines: [String] = ["## Current active priorities"]
        lines.append("")
        for record in priorities {
            lines.append("- \(record.title) (P\(record.priority.rawValue))")
        }
        return lines.joined(separator: "\n")
    }

    private static func footer(inputs: Inputs) -> String {
        var parts: [String] = []
        parts.append("Eidos v\(inputs.appVersion) build \(inputs.appBuild)")
        parts.append("\(inputs.memoryCount) memories on disk")
        parts.append("\(formatBytes(inputs.diskBytes)) total")
        if let armed = inputs.egressArmedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append("Egress lockdown active since \(formatter.string(from: armed))")
        }
        return "_" + parts.joined(separator: " · ") + "._"
    }

    // MARK: - Helpers

    /// Returns the start-of-day 6 days before `endingAt` through
    /// end-of-day `endingAt` — a 7-day inclusive window anchored to
    /// the user's local calendar.
    private static func weekBounds(endingAt: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let endOfDay = calendar.date(
            bySettingHour: 23, minute: 59, second: 59, of: endingAt
        ) ?? endingAt
        let startOfDay = calendar.date(byAdding: .day, value: -6, to: endingAt) ?? endingAt
        let weekStart = calendar.startOfDay(for: startOfDay)
        return (weekStart, endOfDay)
    }

    /// `"Energy → 2 (okay)"` → `2`. Returns nil on any other title
    /// shape so a malformed entry doesn't crash the renderer.
    private static func parseEnergyLevel(from title: String) -> Int? {
        guard let arrowIdx = title.range(of: "→") else { return nil }
        let after = title[arrowIdx.upperBound...].trimmingCharacters(in: .whitespaces)
        let digits = after.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// `"With: foo\nDuration: 15 minutes."` → `15`. Returns nil if the
    /// body doesn't contain the expected `Duration: N minutes` line.
    private static func parseDurationMinutes(from body: String) -> Int? {
        guard let range = body.range(of: "Duration:") else { return nil }
        let after = body[range.upperBound...]
        let digits = after.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func stripPrefix(_ string: String, prefix: String) -> String {
        string.hasPrefix(prefix) ? String(string.dropFirst(prefix.count)) : string
    }

    private static func pluralize(_ singular: String, _ count: Int, plural: String? = nil) -> String {
        count == 1 ? singular : (plural ?? singular + "s")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func formatRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
