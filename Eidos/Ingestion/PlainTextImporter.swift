import Foundation

/// Imports a plain-text / Markdown file straight into the knowledge base.
/// Stripping and splitting are deliberately minimal — `TextChunker`
/// handles chunking for embeddings downstream.
struct PlainTextImporter {

    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    @discardableResult
    func importText(
        _ text: String,
        source: EntrySource = .manual,
        tags: [String] = []
    ) async throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let result = try await repo.insert(content: trimmed, source: source, tags: tags)
        switch result {
        case .inserted: return 1
        case .skippedDuplicate: return 0
        }
    }
}
