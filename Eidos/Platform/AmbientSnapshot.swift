import Foundation

/// A point-in-time snapshot of what the device senses about the user's
/// day — location, motion, health, music, next calendar event. Pulled
/// on-demand when HomeView appears or the briefing is generated, so
/// Eidos has immediate context about what the user was just doing
/// without needing the app to have been open.
///
/// Privacy: every field is local-only. The snapshot itself is never
/// serialised to disk — it's an ephemeral assembly of data the sources
/// already have in their own sandboxes.
struct AmbientSnapshot: Sendable {
    var placeName: String?           // "Home" / "Coffee Labs" / "(37.78, -122.41)"
    var activity: String?            // "walking" / "stationary" / "driving"
    var stepsToday: Int?             // HealthKit / CoreMotion
    var activeMinutesToday: Int?
    var sleepHoursLast: Double?
    var recentlyPlayedSong: String?  // "Drake — God's Plan"
    var nextEventTitle: String?
    var nextEventInMinutes: Int?
    var capturedAt: Date

    /// Compact natural-language "right now" line for the Home view or
    /// injection into the chat system prompt when the user opens the app.
    /// Only the non-nil fields appear — missing data isn't papered over.
    var readable: String {
        var parts: [String] = []
        if let placeName { parts.append("at \(placeName)") }
        if let activity, activity != "unknown", activity != "stationary" {
            parts.append("just was \(activity)")
        }
        if let steps = stepsToday, steps > 0 {
            parts.append("\(steps.formatted()) steps today")
        }
        if let sleep = sleepHoursLast, sleep > 0 {
            parts.append(String(format: "%.1f h sleep", sleep))
        }
        if let song = recentlyPlayedSong {
            parts.append("listened to \(song)")
        }
        if let title = nextEventTitle, let mins = nextEventInMinutes {
            parts.append("next: \(title) in \(mins) min")
        }
        return parts.isEmpty ? "No ambient context available yet." :
            "Context: " + parts.joined(separator: "; ") + "."
    }
}

/// Assembles an `AmbientSnapshot` from the various platform sources.
/// Cheap to call — each source already caches recent state, so this is
/// mostly just reading and combining. Target latency: < 100 ms.
@MainActor
final class AmbientSnapshotAssembler {

    private let location: LocationSource
    private let motion: MotionSource
    private let music: MusicSource
    private let calendar: CalendarSource
    private let health: HealthSource

    init(
        location: LocationSource,
        motion: MotionSource,
        music: MusicSource,
        calendar: CalendarSource,
        health: HealthSource
    ) {
        self.location = location
        self.motion = motion
        self.music = music
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
        // When a significant-change event arrives, `lastFix` populates
        // and subsequent assemblies pick it up naturally. Missing first
        // place → fine; Gemma just omits the place sentence.
        let placeName: String? = location.lastFix?.readable

        // Motion today (6am → now). `insight(from:to:)` is the public
        // API on `MotionSource`.
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let m = await motion.insight(from: startOfDay, to: now)

        // Music — most recent track, if any.
        let recent = await music.recentlyPlayed(limit: 1)
        let recentSong = recent.topTitles.first

        // Next calendar event in the next 7 days.
        let events = await self.calendar.fetchEvents(daysAhead: 7)
        let nextEvent = events.first { $0.startDate > now }
        let nextTitle = nextEvent?.title
        let nextMins = nextEvent.map {
            max(0, Int($0.startDate.timeIntervalSinceNow / 60))
        }

        // Health insight (composite). Sleep is exposed via the insight's
        // `sleepHours` field.
        let h = await health.latestInsight()

        return AmbientSnapshot(
            placeName: placeName,
            activity: m.dominantActivity.rawValue,
            stepsToday: m.steps,
            activeMinutesToday: m.activeMinutes,
            sleepHoursLast: h.sleepHoursLastNight,
            recentlyPlayedSong: recentSong,
            nextEventTitle: nextTitle,
            nextEventInMinutes: nextMins,
            capturedAt: Date()
        )
    }
}
