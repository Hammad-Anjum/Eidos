import UIKit
@preconcurrency import UniformTypeIdentifiers
@preconcurrency import Foundation

/// Share Extension entry point. When the user taps **Share → Eidos**
/// in Safari, Messages, Photos, a text editor, etc., this view
/// controller runs in its own process. It extracts the shared
/// payload, writes a `PendingIngestionItem` to the App Group queue,
/// and finishes immediately. The main app ingests on next launch
/// (or if already running, via NotificationCenter on entering
/// foreground).
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Minimal UI — a spinner while we process.
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await process() }
    }

    private func process() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(); return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                await handle(provider: provider, accompanyingText: item.attributedContentText?.string)
            }
        }
        finish()
    }

    /// Type-sniffing: text, URL, and file payloads are each handled
    /// differently. All end up in the App Group queue as JSON entries.
    private func handle(provider: NSItemProvider, accompanyingText: String?) async {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let urlItem = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                let text = [accompanyingText, urlItem.absoluteString]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                enqueue(text: text, kind: "webClip")
                return
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                enqueue(text: text, kind: "plainText")
                return
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            // Fallback for rich text / code fragments
            if let data = try? await provider.loadDataRepresentation(for: .text) {
                if let text = String(data: data, encoding: .utf8) {
                    enqueue(text: text, kind: "plainText")
                    return
                }
            }
        }
    }

    /// Appends one record to `pending_ingestion.json` in the App Group
    /// container, atomic-write with complete file protection (B6).
    private func enqueue(text: String, kind: String) {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.hissamuddin.eidos"
        )
        guard let container else { return }
        let fileURL = container.appendingPathComponent("pending_ingestion.json")

        struct Item: Codable {
            let id: String
            let kind: String
            let payload: String
            let receivedAt: Date
            let sourceAppName: String?
        }

        var items: [Item] = []
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
        }

        items.append(Item(
            id: UUID().uuidString,
            kind: kind,
            payload: text,
            receivedAt: Date(),
            sourceAppName: Bundle.main.bundleIdentifier
        ))

        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

private extension NSItemProvider {
    /// Sugar for calling the Data-returning overload.
    func loadDataRepresentation(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            loadDataRepresentation(forTypeIdentifier: type.identifier) { data, err in
                if let err { cont.resume(throwing: err) }
                else if let data { cont.resume(returning: data) }
                else { cont.resume(throwing: NSError(domain: "Eidos", code: -1)) }
            }
        }
    }
}
