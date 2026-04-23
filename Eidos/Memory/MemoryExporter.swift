import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Exports the entire memory store as a flat set of `.md` files placed
/// in a single directory under `tmp/`. The caller can then zip it via
/// `FileManager.zipItem` or hand it to a share sheet. We deliberately
/// do NOT compress on-device — the MD files are already small and we'd
/// rather use OS-provided share APIs.
enum MemoryExporter {

    /// Writes a copy of every memory file to a fresh timestamped
    /// directory under `tmp/` and returns its URL. Returns nil on
    /// failure. Directory layout mirrors `Documents/memory/<tier>/<id>.md`.
    static func exportAsZip(manager: MemoryManager) async -> URL? {
        let fm = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let exportRoot = fm.temporaryDirectory
            .appendingPathComponent("eidos-memory-\(timestamp)", isDirectory: true)
        try? fm.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        for tier in MemoryTier.allCases {
            let entries = (try? await manager.list(tier: tier)) ?? []
            guard !entries.isEmpty else { continue }
            let tierDir = exportRoot.appendingPathComponent(tier.rawValue, isDirectory: true)
            try? fm.createDirectory(at: tierDir, withIntermediateDirectories: true)
            for entry in entries {
                let contents = MemoryFrontmatter.render(entry)
                let file = tierDir.appendingPathComponent("\(entry.id.uuidString).md")
                try? contents.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        return exportRoot
    }

    /// Hands the URL to the iOS share sheet. Picks up the topmost
    /// key window at call time. No-op on macOS.
    @MainActor
    static func share(_ url: URL) {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad needs a popover anchor.
        if let popover = vc.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(
                x: root.view.bounds.midX,
                y: root.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        root.topMostViewController.present(vc, animated: true)
        #endif
    }
}

#if canImport(UIKit)
private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController
        }
        if let nav = self as? UINavigationController,
           let visible = nav.visibleViewController {
            return visible.topMostViewController
        }
        if let tab = self as? UITabBarController,
           let selected = tab.selectedViewController {
            return selected.topMostViewController
        }
        return self
    }
}
#endif
