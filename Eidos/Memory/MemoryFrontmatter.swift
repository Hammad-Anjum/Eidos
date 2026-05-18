import Foundation

/// Parses and serializes the YAML-style frontmatter block at the top of a
/// memory `.md` file. We keep this intentionally minimal — just the keys
/// `MemoryEntry` needs — so we don't pull in a full YAML dependency.
///
/// Frontmatter format:
/// ```
/// ---
/// id: <uuid>
/// title: "Escaped title"
/// tier: topic
/// priority: 3
/// tags: [work, deadlines]
/// created_at: 2026-04-20T10:00:00Z
/// updated_at: 2026-04-20T14:30:00Z
/// last_accessed_at: 2026-04-20T14:30:00Z
/// ---
///
/// # Body markdown begins here
/// ```
enum MemoryFrontmatter {

    enum ParseError: Error, LocalizedError {
        case missingDelimiters
        case missingField(String)
        case malformedField(String)

        var errorDescription: String? {
            switch self {
            case .missingDelimiters: "Frontmatter block (--- … ---) not found."
            case .missingField(let key): "Required frontmatter field '\(key)' missing."
            case .malformedField(let key): "Frontmatter field '\(key)' is malformed."
            }
        }
    }

    /// Returns a fresh ISO8601 formatter. We build per call (rather than
    /// caching a shared instance) because `ISO8601DateFormatter` is not
    /// `Sendable`. The cost is negligible for memory I/O cadence.
    private static func isoFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    // MARK: - Encoding

    /// Renders `entry` to its full `.md` file contents (frontmatter + body).
    static func render(_ entry: MemoryEntry) -> String {
        let iso = isoFormatter()
        let tagsRendered = entry.tags.isEmpty
            ? "[]"
            : "[" + entry.tags.map { escapeInline($0) }.joined(separator: ", ") + "]"

        // The `pinned` field is omitted when false to keep older
        // unpinned files identical on re-render (no diff churn). It's
        // explicitly written when true so users can hand-edit the
        // .md if they need to.
        let pinnedLine = entry.pinned ? "pinned: true\n" : ""
        return """
        ---
        id: \(entry.id.uuidString)
        title: "\(escapeQuoted(entry.title))"
        tier: \(entry.tier.rawValue)
        priority: \(entry.priority.rawValue)
        tags: \(tagsRendered)
        \(pinnedLine)created_at: \(iso.string(from: entry.createdAt))
        updated_at: \(iso.string(from: entry.updatedAt))
        last_accessed_at: \(iso.string(from: entry.lastAccessedAt))
        ---

        \(entry.body)
        """
    }

    // MARK: - Decoding

    /// Parses the full contents of a memory `.md` file into a `MemoryEntry`.
    static func parse(_ contents: String) throws -> MemoryEntry {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw ParseError.missingDelimiters
        }
        // Find the closing "---" starting at line 1.
        var closingIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }
        guard let closing = closingIndex else {
            throw ParseError.missingDelimiters
        }

        // Parse key: value pairs between the delimiters.
        var fields: [String: String] = [:]
        for line in lines[1..<closing] {
            let raw = String(line)
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        // Body is everything after the closing delimiter, minus one leading
        // blank line if present.
        var body = ""
        if closing + 1 < lines.count {
            var bodyLines = Array(lines[(closing + 1)...])
            if bodyLines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                bodyLines.removeFirst()
            }
            body = bodyLines.joined(separator: "\n")
        }

        // Decode fields.
        guard let idString = fields["id"], let uuid = UUID(uuidString: idString) else {
            throw ParseError.malformedField("id")
        }
        guard let tierRaw = fields["tier"], let tier = MemoryTier(rawValue: tierRaw) else {
            throw ParseError.malformedField("tier")
        }
        guard let priorityRaw = fields["priority"],
              let priorityInt = Int(priorityRaw),
              let priority = MemoryPriority(rawValue: priorityInt) else {
            throw ParseError.malformedField("priority")
        }
        guard let title = fields["title"].map(unescapeQuoted) else {
            throw ParseError.missingField("title")
        }
        let tags = fields["tags"].map(parseInlineArray) ?? []
        let iso = isoFormatter()
        let createdAt = fields["created_at"].flatMap { iso.date(from: $0) } ?? Date()
        let updatedAt = fields["updated_at"].flatMap { iso.date(from: $0) } ?? createdAt
        let lastAccessedAt = fields["last_accessed_at"].flatMap { iso.date(from: $0) } ?? updatedAt
        // Pinned defaults to false. Accept `true` / `yes` / `1` to be
        // friendly to anyone hand-editing the YAML frontmatter.
        let pinned: Bool = {
            guard let raw = fields["pinned"]?.lowercased() else { return false }
            return raw == "true" || raw == "yes" || raw == "1"
        }()

        return MemoryEntry(
            id: uuid,
            tier: tier,
            title: title,
            body: body,
            priority: priority,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAccessedAt: lastAccessedAt,
            pinned: pinned
        )
    }

    // MARK: - String utilities

    /// Escapes a quoted scalar: `"hi"` → `\"hi\"` inside the literal.
    private static func escapeQuoted(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unescapeQuoted(_ raw: String) -> String {
        // Strip optional surrounding quotes.
        var s = raw
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        return s.replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Simple `[a, b, c]` inline-array parser. Quotes around elements are
    /// stripped; commas inside quoted strings are NOT supported (ok for tags).
    private static func parseInlineArray(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("["), s.hasSuffix("]") else { return [] }
        s = String(s.dropFirst().dropLast())
        return s.split(separator: ",").map {
            unescapeQuoted($0.trimmingCharacters(in: .whitespaces))
        }.filter { !$0.isEmpty }
    }

    /// Escape for use as an element inside an inline array.
    private static func escapeInline(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains(" ") {
            return "\"\(escapeQuoted(s))\""
        }
        return s
    }
}
