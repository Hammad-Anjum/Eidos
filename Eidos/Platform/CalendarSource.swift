import Foundation
import EventKit

struct CalendarEvent: Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?

    var readableDescription: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, h:mm a"
        var s = "\(f.string(from: startDate)) — \(title)"
        if let loc = location, !loc.isEmpty { s += " @ \(loc)" }
        return s
    }
}

actor CalendarSource {
    private let store = EKEventStore()
    private(set) var hasPermission = false

    init() {}

    func requestPermission() async -> Bool {
        hasPermission = (try? await store.requestFullAccessToEvents()) ?? false
        return hasPermission
    }

    func fetchEvents(daysAhead: Int = 7) async -> [CalendarEvent] {
        // TODO(phase 4)
        []
    }

    func fetchReminders() async -> [String] {
        // TODO(phase 4)
        []
    }
}
