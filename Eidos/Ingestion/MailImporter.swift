import Foundation

struct MailImporter {
    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
    }

    /// Imports an mbox file. Per plan.md §B13, real implementation decodes
    /// multipart MIME (Content-Transfer-Encoding: base64 / quoted-printable)
    /// and strips HTML bodies to plain text via NSAttributedString.
    func importMbox(_ content: String) async throws -> Int {
        // TODO(phase 5)
        0
    }
}
