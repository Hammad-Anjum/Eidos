import Foundation

struct PlainTextImporter {
    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    func importText(_ text: String, source: EntrySource = .manual) async throws -> Int {
        // TODO(phase 5)
        0
    }
}
