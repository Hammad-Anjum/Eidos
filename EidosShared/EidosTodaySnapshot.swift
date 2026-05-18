import Foundation

/// Snapshot the main Eidos app writes after each Home appearance,
/// read by the EidosTodayWidget timeline provider. Lives in the
/// App Group container.
///
/// Deliberately small (under 1 KB serialized) so the widget can
/// hydrate it in well under iOS's widget render budget. Larger /
/// richer per-widget content (priority list, body-double session
/// names) belongs in a separate snapshot once the widget gains
/// medium/large families.
public struct EidosTodaySnapshot: Codable, Equatable, Sendable {

    /// One-line agenda summary — the same string `TodayAgendaLine`
    /// renders on the Home tab. Examples:
    ///   - "Quiet day so far."
    ///   - "23 min before standup  ·  5 priorities open"
    public let agendaLine: String

    /// Most recent energy label ("burnout", "low", "okay", "good",
    /// "high"). Empty string when never logged.
    public let energyLabel: String

    /// Number of memory entries currently in `.activePriorities`.
    public let priorityCount: Int

    /// Body-double session count for today (so far).
    public let sessionsToday: Int

    /// When this snapshot was written. Used by the widget to render
    /// a "last updated HH:mm" footer if you want.
    public let updatedAt: Date

    public init(
        agendaLine: String,
        energyLabel: String,
        priorityCount: Int,
        sessionsToday: Int,
        updatedAt: Date = Date()
    ) {
        self.agendaLine = agendaLine
        self.energyLabel = energyLabel
        self.priorityCount = priorityCount
        self.sessionsToday = sessionsToday
        self.updatedAt = updatedAt
    }

    /// Placeholder used by widget previews + first launch before the
    /// main app has had a chance to write a real snapshot.
    public static let placeholder = EidosTodaySnapshot(
        agendaLine: "Open Eidos to populate.",
        energyLabel: "",
        priorityCount: 0,
        sessionsToday: 0
    )
}

/// Read/write helper for the snapshot. Both processes go through this
/// so the on-disk filename stays in one place.
public enum EidosTodaySnapshotStore {

    private static let filename = "eidos-today-snapshot.json"

    /// Writes the snapshot atomically inside the App Group container.
    /// Silent on failure — the widget falls back to `.placeholder` if
    /// the file is missing.
    public static func write(_ snapshot: EidosTodaySnapshot) {
        guard let url = SharedStore.sharedFileURL(filename) else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort; nothing actionable on either side.
        }
    }

    /// Reads the snapshot from the App Group container, falling back
    /// to `.placeholder` if it doesn't exist or fails to decode.
    public static func read() -> EidosTodaySnapshot {
        guard let url = SharedStore.sharedFileURL(filename),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(EidosTodaySnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}
