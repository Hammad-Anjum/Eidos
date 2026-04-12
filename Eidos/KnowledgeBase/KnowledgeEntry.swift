import Foundation
import SwiftData
import CryptoKit

enum EntrySource: String, Codable, Sendable {
    case calendar
    case contact
    case note
    case voice
    case whatsappExport = "whatsapp_export"
    case mailExport = "mail_export"
    case webClip = "web_clip"
    case manual
    case skillOutput = "skill_output"
    case shareExtension = "share_extension"
}

@Model
final class KnowledgeEntry {
    var id: UUID
    var content: String
    var contentHash: String   // B8: SHA256 of content, used for idempotent ingestion
    var source: String        // EntrySource.rawValue — SwiftData needs raw types
    var createdAt: Date
    var tags: [String]
    var metadata: String      // JSON string for source-specific fields

    @Relationship(deleteRule: .cascade)
    var embeddings: [EmbeddingRecord] = []

    init(
        content: String,
        source: EntrySource,
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.content = content
        self.contentHash = KnowledgeEntry.hash(of: content)
        self.source = source.rawValue
        self.createdAt = Date()
        self.tags = tags
        self.metadata = (try? JSONEncoder().encode(metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    var entrySource: EntrySource {
        EntrySource(rawValue: source) ?? .manual
    }

    // B8: stable content hash for idempotent ingestion. SHA256 is required
    // (Swift's `Hasher` is process-seeded, so its output cannot be used for
    // cross-launch dedup).
    static func hash(of content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
