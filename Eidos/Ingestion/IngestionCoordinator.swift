import Foundation

/// Shape of an item in the App-Group ingestion queue. The Share
/// Extension writes these; the main app consumes them on launch.
struct PendingIngestionItem: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case plainText
        case webClip
        case whatsappExport
        case mboxMail
    }

    let id: UUID
    let kind: Kind
    let payload: String              // raw content (bytes are base64 for binary)
    let receivedAt: Date
    let sourceAppName: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        payload: String,
        receivedAt: Date = Date(),
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.receivedAt = receivedAt
        self.sourceAppName = sourceAppName
    }
}

/// Coordinates bulk ingestion from:
/// 1. The App-Group queue (populated by the Share Extension)
/// 2. Direct calls from `IngestView` (user pastes text, picks a file)
///
/// Writes go through the type-specific importers which in turn call
/// `KnowledgeRepository.insert(...)` with deduping and background
/// embedding.
@MainActor
@Observable
final class IngestionCoordinator {

    var pendingCount = 0
    var isProcessing = false
    var lastResult: String?

    private let repo: KnowledgeRepository
    private let plainText: PlainTextImporter
    private let whatsapp: WhatsAppImporter
    private let mail: MailImporter

    init(repo: KnowledgeRepository) {
        self.repo = repo
        self.plainText = PlainTextImporter(repo: repo)
        self.whatsapp = WhatsAppImporter(repo: repo)
        self.mail = MailImporter(repo: repo)
        refresh()
    }

    // MARK: - Queue management

    /// Reads the App-Group JSON queue and updates `pendingCount`. Safe
    /// to call whenever; reads are cheap and idempotent.
    func refresh() {
        let items = (try? readQueue()) ?? []
        pendingCount = items.count
    }

    /// Drains the App-Group queue one item at a time, importing each.
    /// On success, the queue file is rewritten with the remaining items;
    /// failures leave the item in place for retry.
    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        var items = (try? readQueue()) ?? []
        var imported = 0
        var failed = 0
        var remaining: [PendingIngestionItem] = []

        for item in items {
            do {
                imported += try await importOne(item)
            } catch {
                failed += 1
                remaining.append(item)
            }
        }
        items = remaining
        try? writeQueue(items)
        pendingCount = items.count

        var parts: [String] = []
        if imported > 0 { parts.append("\(imported) imported") }
        if failed > 0 { parts.append("\(failed) kept for retry") }
        lastResult = parts.isEmpty ? "Nothing to do." : parts.joined(separator: ", ")
    }

    // MARK: - Direct imports (from UI)

    @discardableResult
    func importPlainText(_ text: String, source: EntrySource = .manual) async throws -> Int {
        try await plainText.importText(text, source: source)
    }

    @discardableResult
    func importWhatsAppExport(_ text: String) async throws -> Int {
        try await whatsapp.importText(text)
    }

    @discardableResult
    func importMbox(_ content: String) async throws -> Int {
        try await mail.importMbox(content)
    }

    // MARK: - Queue I/O

    private func readQueue() throws -> [PendingIngestionItem] {
        guard let url = AppGroupStore.pendingIngestionFile,
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PendingIngestionItem].self, from: data)
    }

    private func writeQueue(_ items: [PendingIngestionItem]) throws {
        guard let url = AppGroupStore.pendingIngestionFile else { return }
        let data = try JSONEncoder().encode(items)
        try AppGroupStore.writeProtected(data, to: url)
    }

    // MARK: - Per-item dispatch

    private func importOne(_ item: PendingIngestionItem) async throws -> Int {
        switch item.kind {
        case .plainText:
            return try await plainText.importText(item.payload, source: .shareExtension)
        case .webClip:
            return try await plainText.importText(item.payload, source: .webClip)
        case .whatsappExport:
            return try await whatsapp.importText(item.payload)
        case .mboxMail:
            return try await mail.importMbox(item.payload)
        }
    }
}
