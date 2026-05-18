import Foundation

/// Read/write contract shared between the main Eidos app and the widget
/// extension. Uses an App Group container so both processes see the same
/// file. Falls back to the calling process's Documents dir when the App
/// Group isn't provisioned (e.g. free Personal Team without entitlement).
///
/// Tonight (medical-helper pivot) this is a thin file-coordination helper.
/// Tomorrow it carries the medication-countdown snapshot the widget reads.
public enum SharedStore {

    /// Must match the App Group declared in both targets' entitlements.
    public static let appGroupID = "group.com.hissamuddin.eidos"

    /// The directory both processes can reach. Returns nil only if even
    /// the fallback (Documents) is unavailable.
    public static var containerURL: URL? {
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

    /// Returns the URL inside the shared container for `filename`, or nil
    /// if the container is unavailable.
    public static func sharedFileURL(_ filename: String) -> URL? {
        containerURL?.appendingPathComponent(filename)
    }
}
