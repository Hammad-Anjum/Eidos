import Foundation
import ActivityKit

/// Data ferried between the main app and the Live Activity widget.
/// Two distinct states are multiplexed through this single type so we
/// only register one Activity with iOS:
///
/// - `.generating` — while Gemma is producing the briefing. Pulsing
///   rainbow glow in Dynamic Island, streaming preview text.
/// - `.meetingSoon` — 0-15 min before a calendar event. Countdown +
///   meeting title.
public struct DigestActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable {
        public enum Phase: String, Codable, Hashable {
            case generating
            case meetingSoon
        }

        public var phase: Phase
        public var title: String               // "Generating briefing…" or meeting title
        public var detail: String              // streaming preview or "in 4 min"
        public var startsAt: Date?             // meeting start time (phase = meetingSoon only)
        public var symbolName: String          // SF Symbol to render

        public init(phase: Phase, title: String, detail: String, startsAt: Date? = nil, symbolName: String) {
            self.phase = phase
            self.title = title
            self.detail = detail
            self.startsAt = startsAt
            self.symbolName = symbolName
        }
    }

    // Static attributes: rarely change during activity lifetime.
    public var kind: String

    public init(kind: String = "eidos") { self.kind = kind }
}
