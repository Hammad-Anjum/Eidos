import UIKit
import UniformTypeIdentifiers

// Share Extension entry point. Uses App Group
// `group.com.eidos.shared` (B4 rename) to hand off shared content to the
// main app for ingestion. Writes the pending queue file with
// `.completeFileProtection` (B6).
final class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await process() }
    }

    private func process() async {
        // TODO(phase 5): walk extensionContext?.inputItems, extract text /
        // url / fileURL attachments, append to the pending_ingestion.json
        // queue, reject oversize non-text attachments early.
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
