import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Splits an mbox archive into individual messages and imports each as
/// a knowledge entry. Minimal MIME handling: decodes quoted-printable
/// transfer encoding, strips HTML to plain text via NSAttributedString.
/// Full multipart/alternative handling is out of scope for Phase 5 — if
/// the mbox is HTML-only, we still get a readable dump.
struct MailImporter {

    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    @discardableResult
    func importMbox(_ content: String) async throws -> Int {
        let messages = Self.split(content)
        var imported = 0
        for message in messages {
            guard let parsed = Self.extractReadable(message) else { continue }
            let result = try await repo.insert(
                content: parsed.body,
                source: .mailExport,
                tags: parsed.from.map { [$0] } ?? [],
                metadata: parsed.metadata
            )
            if case .inserted = result { imported += 1 }
        }
        return imported
    }

    // MARK: - mbox splitting

    /// mbox messages begin with a line starting with `From `. We split on
    /// that marker rather than just splitting by blank lines.
    static func split(_ content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var messages: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.hasPrefix("From "), !current.isEmpty {
                messages.append(current)
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { messages.append(current) }
        return messages.map { $0.joined(separator: "\n") }
    }

    // MARK: - Extraction

    struct Parsed {
        var from: String?
        var subject: String?
        var date: String?
        var body: String

        var metadata: [String: String] {
            var m: [String: String] = [:]
            if let from { m["from"] = from }
            if let subject { m["subject"] = subject }
            if let date { m["date"] = date }
            return m
        }
    }

    static func extractReadable(_ message: String) -> Parsed? {
        // Split headers / body on first blank line.
        let parts = message.components(separatedBy: "\n\n")
        guard parts.count >= 2 else { return nil }
        let headerBlock = parts[0]
        let bodyBlock = parts.dropFirst().joined(separator: "\n\n")

        let headers = parseHeaders(headerBlock)
        let encoding = headers["content-transfer-encoding"]?.lowercased()
        let decodedBody = decode(bodyBlock, encoding: encoding)
        let plainBody = stripHTML(decodedBody).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainBody.isEmpty else { return nil }

        return Parsed(
            from: headers["from"],
            subject: headers["subject"],
            date: headers["date"],
            body: [
                headers["subject"].map { "Subject: \($0)" },
                headers["from"].map { "From: \($0)" },
                "",
                plainBody,
            ].compactMap { $0 }.joined(separator: "\n")
        )
    }

    private static func parseHeaders(_ block: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        for line in block.components(separatedBy: "\n") {
            // Folded continuation lines begin with whitespace.
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), let key = currentKey {
                result[key] = (result[key] ?? "") + " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                result[key] = value
                currentKey = key
            }
        }
        return result
    }

    private static func decode(_ body: String, encoding: String?) -> String {
        switch encoding {
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        case "base64":
            let compact = body.components(separatedBy: .whitespacesAndNewlines).joined()
            if let data = Data(base64Encoded: compact), let s = String(data: data, encoding: .utf8) {
                return s
            }
            return body
        default:
            return body
        }
    }

    private static func decodeQuotedPrintable(_ input: String) -> String {
        var result = ""
        var i = input.startIndex
        while i < input.endIndex {
            let c = input[i]
            if c == "=" {
                let afterEq = input.index(after: i)
                if afterEq == input.endIndex { break }
                // Soft line break `=\n`
                if input[afterEq] == "\n" {
                    i = input.index(after: afterEq)
                    continue
                }
                let end = input.index(afterEq, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
                let hex = String(input[afterEq..<end])
                if let value = UInt8(hex, radix: 16) {
                    result.append(Character(UnicodeScalar(value)))
                    i = end
                    continue
                }
            }
            result.append(c)
            i = input.index(after: i)
        }
        return result
    }

    private static func stripHTML(_ s: String) -> String {
        // Only run the HTML parser if the content looks like HTML — otherwise
        // we strip entities unnecessarily and corrupt plain-text mail.
        guard s.contains("<") && (s.contains("</") || s.contains("/>") || s.contains("<!DOCTYPE")) else {
            return s
        }
        #if canImport(UIKit)
        guard let data = s.data(using: .utf8) else { return s }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attr.string
        }
        #endif
        return s
    }
}
