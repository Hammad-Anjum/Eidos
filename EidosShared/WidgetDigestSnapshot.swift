import Foundation

/// What the widget renders. Kept tiny — widgets have a ~30 MB memory
/// budget and <10 ms render time, so we pre-compute everything here and
/// the widget only does layout work.
public struct WidgetDigestSnapshot: Codable, Equatable, Sendable {

    public struct EventSummary: Codable, Equatable, Sendable {
        public var title: String
        public var start: Date
        public var location: String?

        public init(title: String, start: Date, location: String?) {
            self.title = title
            self.start = start
            self.location = location
        }
    }

    public var greeting: String                 // "Good morning" etc.
    public var briefing: String                 // 1-3 sentences
    public var nextEvent: EventSummary?
    public var eventsToday: Int
    public var remindersOpen: Int
    public var generatedAt: Date

    public init(
        greeting: String,
        briefing: String,
        nextEvent: EventSummary?,
        eventsToday: Int,
        remindersOpen: Int,
        generatedAt: Date = Date()
    ) {
        self.greeting = greeting
        self.briefing = briefing
        self.nextEvent = nextEvent
        self.eventsToday = eventsToday
        self.remindersOpen = remindersOpen
        self.generatedAt = generatedAt
    }

    /// Placeholder rendered when the widget has no data yet (e.g. just
    /// installed) or when preview is requested by WidgetKit.
    public static let placeholder = WidgetDigestSnapshot(
        greeting: "Good morning",
        briefing: "Your Eidos briefing will appear here after your first digest.",
        nextEvent: nil,
        eventsToday: 0,
        remindersOpen: 0
    )
}
