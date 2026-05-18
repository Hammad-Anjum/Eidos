import Foundation

/// A point-in-time snapshot of what the device senses about the user's
/// day — location, health, next calendar event. Pulled on-demand when
/// the medication helper assembles its briefing or seeds chat context.
///
/// Privacy: every field is local-only. The snapshot itself is never
/// serialised to disk — it's an ephemeral assembly of data the sources
/// already have in their own sandboxes.
///
/// Medical-helper note: the previous Eidos build also pulled motion and
/// music. Those signals are not relevant to medication adherence, so the
/// fields are gone. Kept: location (for arrived-home dose triggers),
/// health (sleep/HR for adherence correlation), and the next calendar
/// event (so dose reminders can avoid scheduling conflicts).
struct AmbientSnapshot: Sendable {
    var placeName: String?           // "Home" / "Pharmacy" / "(37.78, -122.41)"
    var sleepHoursLast: Double?
    var nextEventTitle: String?
    var nextEventInMinutes: Int?
    var capturedAt: Date

    /// Compact natural-language "right now" line for the Home view or
    /// injection into the chat system prompt when the user opens the app.
    /// Only the non-nil fields appear — missing data isn't papered over.
    var readable: String {
        var parts: [String] = []
        if let placeName { parts.append("at \(placeName)") }
        if let sleep = sleepHoursLast, sleep > 0 {
            parts.append(String(format: "%.1f h sleep", sleep))
        }
        if let title = nextEventTitle, let mins = nextEventInMinutes {
            parts.append("next: \(title) in \(mins) min")
        }
        return parts.isEmpty ? "No ambient context available yet." :
            "Context: " + parts.joined(separator: "; ") + "."
    }
}

/// Assembles an `AmbientSnapshot` from the medical-relevant platform
/// sources. Cheap to call — each source already caches recent state.
/// Target latency: < 100 ms.
@MainActor
final class AmbientSnapshotAssembler {

    private let location: LocationSource
    private let calendar: CalendarSource
    private let health: HealthSource

    init(
        location: LocationSource,
        calendar: CalendarSource,
        health: HealthSource
    ) {
        self.location = location
        self.calendar = calendar
        self.health = health
    }

    /// Assembles a snapshot. Any individual source that fails /
    /// lacks permission simply contributes nil — the snapshot still
    /// returns with whatever is available.
    func assemble() async -> AmbientSnapshot {
        // Place: prefer a cached fix (instant). We deliberately do NOT
        // call `currentFix()` here because it triggers a reverse-geocode
        // round-trip (~0.5-2s) and can block a first-turn chat reply.
        let placeName: String? = location.lastFix?.readable

        // Next calendar event in the next 7 days.
        let now = Date()
        let events = await self.calendar.fetchEvents(daysAhead: 7)
        let nextEvent = events.first { $0.startDate > now }
        let nextTitle = nextEvent?.title
        let nextMins = nextEvent.map {
            max(0, Int($0.startDate.timeIntervalSinceNow / 60))
        }

        // Health insight (composite). Sleep is exposed via the insight's
        // `sleepHoursLastNight` field.
        let h = await health.latestInsight()

        return AmbientSnapshot(
            placeName: placeName,
            sleepHoursLast: h.sleepHoursLastNight,
            nextEventTitle: nextTitle,
            nextEventInMinutes: nextMins,
            capturedAt: Date()
        )
    }
}
