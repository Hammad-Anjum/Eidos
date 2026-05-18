import Foundation

/// Builds the "session report" — a tighter, summarized briefing meant
/// to be readable in two minutes by a professional.
///
/// **Distinct from `WeeklySummaryBuilder`:**
///
/// | Aspect | `WeeklySummaryBuilder` | `TherapistReportBuilder` |
/// |---|---|---|
/// | Audience | The user (or anyone) | A clinician / professional |
/// | Generation | Pure deterministic | Hybrid: deterministic facts + Gemma-summarized themes |
/// | Length | Long, enumerative | Short, structured |
/// | Where | Memory tab toolbar | Settings → Share |
///
/// **Tonal rules** (carried from `CLAUDE.md`):
/// - Never uses "Doctor / Therapist / Coach" in the document or in the
///   surfacing copy. Recipient framing is *"a professional"*.
/// - The model is constrained by tight prompts to a neutral, factual
///   register — no diagnostic language, no advice, no judgments.
/// - Every section is provenance-marked so the reader knows which
///   bullets were drafted by the on-device LLM versus mechanically
///   enumerated.
/// - The preview view that wraps this builder MUST give the user a
///   chance to edit before sharing. Hallucinated bullets going to a
///   clinician's inbox unverified is the failure mode this exists
///   to prevent.
///
/// **Simulator behavior:** the Gemma-narrated sections show clear
/// placeholders so demo screenshots from the sim don't look like real
/// summaries. Real Gemma runs on Mac Catalyst and physical iPhone.
enum TherapistReportBuilder {

    /// Everything the builder needs. Collected by the caller so the
    /// builder itself stays pure and (for the deterministic parts)
    /// testable.
    struct Inputs: Sendable {
        let allRecords: [MemoryIndexRecord]
        /// Full bodies of journal entries this week. Source for Gemma's
        /// theme summary; never inlined into the report (privacy).
        let journalBodies: [(date: Date, body: String)]
        let memoryCount: Int
        let diskBytes: Int64
        let weekEnding: Date
        let egressArmedAt: Date?
        let appVersion: String
        let appBuild: String
    }

    /// Builds the report markdown. Async because the themes + notable-
    /// entries sections await `GemmaSession.generate(...)`. The Gemma
    /// calls run sequentially (the inference lock makes parallel
    /// pointless) and degrade gracefully — if generation fails, the
    /// affected section renders an honest `[summary unavailable]`
    /// stub rather than fabricating.
    static func build(inputs: Inputs, gemma: GemmaSession) async -> String {
        let (weekStart, weekEnd) = weekBounds(endingAt: inputs.weekEnding)

        var lines: [String] = []
        lines.append("# Eidos — Session report")
        lines.append("**\(formatRange(weekStart, weekEnd))**")
        lines.append("")
        lines.append("> Self-reported data, captured on the user's own device.")
        lines.append("> Themes below were drafted by an on-device language model — verify against the user's full entries.")
        lines.append("> This is not a diagnostic record.")
        lines.append("")
        lines.append("---")
        lines.append("")

        // ── At a glance ─────────────────────────────────────────────
        lines.append("## At a glance  `[deterministic]`")
        lines.append("")
        let weekRecords = inputs.allRecords.filter { rec in
            (rec.updatedAt >= weekStart && rec.updatedAt <= weekEnd) ||
            (rec.lastAccessedAt >= weekStart && rec.lastAccessedAt <= weekEnd)
        }

        let journalCount    = weekRecords.filter { $0.tags.contains("journal") }.count
        let bodyDoubleCount = weekRecords.filter { $0.tags.contains("body-double") }.count
        let sceneCount      = weekRecords.filter { $0.tags.contains("scene") || $0.tags.contains("look-mode") }.count
        let picksCount      = weekRecords.filter {
            $0.tier == .activePriorities &&
            $0.lastAccessedAt > $0.updatedAt
        }.count
        let energyRecords   = weekRecords.filter { $0.tags.contains("energy") }
        let energyBuckets   = bucketEnergy(energyRecords)
        let mostCommonEnergy = energyBuckets.max(by: { $0.value < $1.value })

        lines.append("- **Journal entries:** \(journalCount)")
        lines.append("- **Body-double sessions:** \(bodyDoubleCount)")
        if sceneCount > 0  { lines.append("- **Scene break-down requests:** \(sceneCount)") }
        if picksCount > 0  { lines.append("- **Tasks picked via in-app picker:** \(picksCount)") }
        if let energy = mostCommonEnergy {
            let label = energyLabels[energy.key] ?? "?"
            lines.append("- **Most-logged energy state:** \(label) (\(energy.value) of \(energyRecords.count) logs)")
        }
        let burnoutLogs = energyBuckets[0] ?? 0
        if burnoutLogs > 0 {
            lines.append("- **Burnout-level logs (0/4):** \(burnoutLogs)")
        }
        lines.append("")

        // ── Themes (Gemma) ──────────────────────────────────────────
        lines.append("## Themes  `[on-device summary — verify]`")
        lines.append("")
        if inputs.journalBodies.isEmpty {
            lines.append("_No journal entries this week to summarize._")
        } else {
            let themes = await summarizeThemes(inputs.journalBodies, gemma: gemma)
            lines.append(themes)
        }
        lines.append("")

        // ── Active commitments (verbatim) ───────────────────────────
        let priorities = inputs.allRecords
            .filter { $0.tier == .activePriorities }
            .sorted { $0.priority.rawValue < $1.priority.rawValue }
        if !priorities.isEmpty {
            lines.append("## Active commitments  `[user's own words]`")
            lines.append("")
            for record in priorities.prefix(8) {
                lines.append("- \(record.title) (P\(record.priority.rawValue))")
            }
            lines.append("")
        }

        // ── Notable entries (Gemma) ─────────────────────────────────
        if !inputs.journalBodies.isEmpty {
            lines.append("## Notable entries  `[on-device selection — verify]`")
            lines.append("")
            let notable = await selectNotableEntries(inputs.journalBodies, gemma: gemma)
            lines.append(notable)
            lines.append("")
        }

        // ── Footer ──────────────────────────────────────────────────
        lines.append("---")
        lines.append("")
        lines.append(footer(inputs: inputs))
        return lines.joined(separator: "\n")
    }

    /// Writes the markdown to `tmp/eidos-report-YYYY-MM-DD.md` ready
    /// for the share sheet.
    static func writeToTempFile(_ markdown: String, weekEnding: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "eidos-report-\(formatter.string(from: weekEnding)).md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Gemma callers

    /// Asks Gemma for 3-4 short theme bullets from journal bodies.
    /// Bounded by `maxJournalCharsPerSection` to keep prefill RAM
    /// reasonable even when the user has a heavy week of entries.
    /// On simulator returns a placeholder — MLX inference is a mock
    /// there and would emit unusable text.
    private static func summarizeThemes(
        _ entries: [(date: Date, body: String)],
        gemma: GemmaSession
    ) async -> String {
        #if targetEnvironment(simulator)
        return "_On a real device, Eidos summarizes the week's recurring themes here using on-device Gemma 4. The simulator does not run the real model._"
        #else
        let corpus = entries
            .sorted { $0.date < $1.date }
            .map { "[\(formatDate($0.date))] \($0.body)" }
            .joined(separator: "\n\n")
            .prefix(maxJournalCharsPerSection)

        let systemPrompt = """
        You read a user's private journal entries and summarize recurring \
        themes for a clinical context. Output ONLY 3 to 4 short bullet \
        points (each under 25 words) capturing patterns across the week. \
        Use the user's own vocabulary. Use neutral, factual language. \
        Do NOT diagnose. Do NOT use medical or therapeutic terms. Do NOT \
        give advice. Do NOT include a header or preamble — start \
        directly with the first bullet.
        """
        let messages: [[String: String]] = [
            ["role": "system",  "content": systemPrompt],
            ["role": "user",    "content": String(corpus)],
        ]

        do {
            let stream = try await gemma.generate(messages: messages, reasoning: .fast)
            var out = ""
            for try await chunk in stream {
                out += chunk
                if out.count > 1200 { break }  // hard cap — themes are short
            }
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "_[summary unavailable — try regenerating later]_" : trimmed
        } catch {
            EidosLogger.shared.error(.model,
                event: "therapist-report.themes.failed",
                error: error, failure: .modelGenerate)
            return "_[summary unavailable — Gemma generation failed]_"
        }
        #endif
    }

    /// Asks Gemma to pick up to 2 verbatim excerpts from journal
    /// entries that would be useful for a clinician to read directly.
    /// Output format is constrained to `> "quote" — date` so it's
    /// trivially diff-able against the source entries in the appendix.
    private static func selectNotableEntries(
        _ entries: [(date: Date, body: String)],
        gemma: GemmaSession
    ) async -> String {
        #if targetEnvironment(simulator)
        return "_On a real device, Eidos extracts up to two verbatim quotes here using on-device Gemma 4._"
        #else
        let corpus = entries
            .sorted { $0.date > $1.date }  // recent first
            .map { "[\(formatDate($0.date))] \($0.body)" }
            .joined(separator: "\n\n")
            .prefix(maxJournalCharsPerSection)

        let systemPrompt = """
        From the user's journal entries, pick up to 2 short excerpts that \
        would be most useful for a professional reader to see verbatim. \
        Each excerpt must be a direct quote of fewer than 30 words from a \
        single entry — do not paraphrase, do not summarize, do not invent. \
        Format each excerpt on its own line as:
        > "quote" — date
        Output ONLY the excerpt lines. No header, no preamble, no commentary.
        """
        let messages: [[String: String]] = [
            ["role": "system",  "content": systemPrompt],
            ["role": "user",    "content": String(corpus)],
        ]

        do {
            let stream = try await gemma.generate(messages: messages, reasoning: .fast)
            var out = ""
            for try await chunk in stream {
                out += chunk
                if out.count > 800 { break }
            }
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "_[no notable excerpt extracted]_" : trimmed
        } catch {
            EidosLogger.shared.error(.model,
                event: "therapist-report.notable.failed",
                error: error, failure: .modelGenerate)
            return "_[excerpt extraction unavailable — Gemma generation failed]_"
        }
        #endif
    }

    // MARK: - Helpers

    /// Char cap per Gemma section input. Tight enough that prefill
    /// stays inside iPhone Metal heap budget even with the E4B variant.
    private static let maxJournalCharsPerSection = 6_000

    private static let energyLabels: [Int: String] = [
        0: "burnout", 1: "low", 2: "okay", 3: "good", 4: "high",
    ]

    private static func bucketEnergy(_ entries: [MemoryIndexRecord]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for entry in entries {
            if let level = parseEnergyLevel(from: entry.title) {
                counts[level, default: 0] += 1
            }
        }
        return counts
    }

    private static func parseEnergyLevel(from title: String) -> Int? {
        guard let arrowIdx = title.range(of: "→") else { return nil }
        let after = title[arrowIdx.upperBound...].trimmingCharacters(in: .whitespaces)
        return Int(after.prefix(while: { $0.isNumber }))
    }

    private static func weekBounds(endingAt: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let endOfDay = calendar.date(
            bySettingHour: 23, minute: 59, second: 59, of: endingAt
        ) ?? endingAt
        let startDay = calendar.date(byAdding: .day, value: -6, to: endingAt) ?? endingAt
        return (calendar.startOfDay(for: startDay), endOfDay)
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

    private static func footer(inputs: Inputs) -> String {
        var parts: [String] = []
        parts.append("Eidos v\(inputs.appVersion) build \(inputs.appBuild)")
        parts.append("\(inputs.memoryCount) memories")
        parts.append("\(formatBytes(inputs.diskBytes))")
        if let armed = inputs.egressArmedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append("Egress lockdown since \(formatter.string(from: armed))")
        }
        return "_" + parts.joined(separator: " · ") + "._"
    }
}
