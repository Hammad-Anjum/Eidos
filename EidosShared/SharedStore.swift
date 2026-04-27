import Foundation

/// Read/write contract shared between the main Eidos app and the widget
/// extension. Uses an App Group container so both processes see the same
/// file. Falls back to the calling process's Documents dir when the App
/// Group isn't provisioned (e.g. free Personal Team without entitlement).
public enum SharedStore {

    /// Must match the App Group declared in both targets' entitlements.
    public static let appGroupID = "group.com.hissamuddin.eidos"

    private static let filename = "widget-digest.json"

    /// The directory both processes can reach. Returns nil only if even
    /// the fallback (Documents) is unavailable.
    static var containerURL: URL? {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return group
        }
        // Fallback for dev builds without App Group entitlement.
        return try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
    }

    private static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(filename)
    }

    // MARK: - Digest snapshot

    /// Persists `snapshot` so the widget can read it on its next refresh.
    public static func writeDigest(_ snapshot: WidgetDigestSnapshot) {
        guard let url = snapshotURL else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Reads the most-recent snapshot, or nil if no digest has been
    /// generated yet on this install.
    public static func readDigest() -> WidgetDigestSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetDigestSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
