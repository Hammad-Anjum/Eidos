import Foundation

struct ImportedMessage: Sendable, Equatable {
    let timestamp: Date?
    let sender: String
    let content: String

    var readable: String {
        if let timestamp {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return "[\(f.string(from: timestamp))] \(sender): \(content)"
        }
        return "\(sender): \(content)"
    }
}

/// Parses a WhatsApp text export (`Export Chat → Without Media`). Locales
/// format the header line differently — this parser handles several common
/// patterns (B12 in plan.md).
///
/// Supported header shapes (case-insensitive on AM/PM):
///   `[M/D/YY, H:MM:SS AM] Name: message`
///   `[M/D/YYYY, HH:MM:SS] Name: message`
///   `M/D/YY, H:MM - Name: message`
///   `D.M.YYYY, HH:MM - Name: message`
///
/// Invisible LTR/RTL marks and BOMs are stripped before matching.
struct WhatsAppImporter {

    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    /// Parses `text`, builds one `KnowledgeEntry` (with all messages in
    /// one `content` block), and inserts it. Returns the number of
    /// messages parsed (0 if the format wasn't recognised).
    @discardableResult
    func importText(_ text: String) async throws -> Int {
        let messages = Self.parse(text)
        guard !messages.isEmpty else { return 0 }

        let body = messages.map(\.readable).joined(separator: "\n")
        let senders = Set(messages.map(\.sender))
        let first = messages.first?.timestamp
        let last = messages.last?.timestamp

        var meta: [String: String] = [
            "message_count": String(messages.count),
            "participants": senders.sorted().joined(separator: ", "),
        ]
        if let first { meta["first"] = ISO8601DateFormatter().string(from: first) }
        if let last { meta["last"] = ISO8601DateFormatter().string(from: last) }

        _ = try await repo.insert(
            content: body,
            source: .whatsappExport,
            tags: Array(senders),
            metadata: meta
        )
        return messages.count
    }

    // MARK: - Pure parsing (no I/O — unit-testable)

    static func parse(_ raw: String) -> [ImportedMessage] {
        let cleaned = stripInvisibles(raw)
        let lines = cleaned.components(separatedBy: .newlines)
        var messages: [ImportedMessage] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if let match = parseHeader(trimmed) {
                messages.append(match)
            } else if let last = messages.last {
                // Continuation line — append to the previous message.
                let combined = last.content.isEmpty ? trimmed : last.content + "\n" + trimmed
                messages[messages.count - 1] = ImportedMessage(
                    timestamp: last.timestamp,
                    sender: last.sender,
                    content: combined
                )
            }
        }
        return messages
    }

    // MARK: - Regex

    private static let headerRegex: NSRegularExpression = {
        // Header: optional `[ ]`, date separators `/.-`, time with optional seconds / am-pm,
        // optional dash between header and sender, sender up to colon, body.
        let pattern = #"^\[?(?<date>\d{1,4}[\./\-]\d{1,2}[\./\-]\d{1,4}(?:,?\s*)\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp][Mm])?)\]?\s*[-–—]?\s*(?<sender>[^:]{1,80}):\s*(?<body>.*)$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let dateFormats: [String] = [
        "M/d/yy, h:mm a",
        "M/d/yy, h:mm:ss a",
        "M/d/yyyy, h:mm a",
        "M/d/yyyy, h:mm:ss a",
        "M/d/yy, HH:mm",
        "M/d/yyyy, HH:mm",
        "M/d/yyyy, HH:mm:ss",
        "d/M/yy, HH:mm",
        "d/M/yyyy, HH:mm",
        "d/M/yyyy, HH:mm:ss",
        "d.M.yyyy, HH:mm",
        "yyyy-MM-dd HH:mm:ss",
    ]

    private static func parseHeader(_ line: String) -> ImportedMessage? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = headerRegex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func capture(_ name: String) -> String? {
            let r = match.range(withName: name)
            guard r.location != NSNotFound, let sr = Range(r, in: line) else { return nil }
            return String(line[sr]).trimmingCharacters(in: .whitespaces)
        }
        guard let dateStr = capture("date"),
              let sender = capture("sender"),
              let body = capture("body") else {
            return nil
        }
        return ImportedMessage(
            timestamp: parseDate(dateStr),
            sender: sender,
            content: body
        )
    }

    private static func parseDate(_ s: String) -> Date? {
        let normalised = s.replacingOccurrences(of: "\u{00A0}", with: " ")  // NBSP
                          .replacingOccurrences(of: ".", with: "/")
                          .replacingOccurrences(of: "-", with: "/")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: normalised) { return d }
        }
        return nil
    }

    private static func stripInvisibles(_ s: String) -> String {
        let junk: Set<Character> = ["\u{200E}", "\u{200F}", "\u{FEFF}", "\u{200B}", "\u{202A}", "\u{202C}"]
        return String(s.filter { !junk.contains($0) })
    }
}
