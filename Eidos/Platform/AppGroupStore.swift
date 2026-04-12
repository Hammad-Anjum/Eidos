import Foundation

// Shared read/write helpers for the App Group container that Eidos and the
// Share Extension both use. Group ID: group.com.eidos.shared (B4 rename).
enum AppGroupStore {
    static let appGroupID = "group.com.eidos.shared"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var pendingIngestionFile: URL? {
        container?.appendingPathComponent("pending_ingestion.json")
    }

    /// B6: write App Group files with `.complete` protection so they're
    /// unreadable while the device is locked.
    static func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
