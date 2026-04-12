import Foundation

struct WhatsAppImporter {
    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    /// Imports a WhatsApp .txt export. Per plan.md §B12, real implementation
    /// tries multiple locale patterns (UK/EU, US 12h, etc.) and picks the
    /// first that matches.
    func importText(_ text: String) async throws -> Int {
        // TODO(phase 5)
        0
    }
}
