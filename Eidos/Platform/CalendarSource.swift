import Foundation
import EventKit

struct CalendarEvent: Sendable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let isAllDay: Bool

    var readableDescription: String {
        let f = DateFormatter()
        f.dateFormat = isAllDay ? "EEE d MMM (all day)" : "EEE d MMM, h:mm a"
        var s = "\(f.string(from: startDate)) — \(title)"
        if let loc = location, !loc.isEmpty { s += " @ \(loc)" }
        return s
    }
}

struct Reminder: Sendable, Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let notes: String?
}

/// EventKit wrapper for calendar events and reminders. All work happens
/// inside the actor so concurrent callers can't race `EKEventStore`.
actor CalendarSource {

    private let store = EKEventStore()
    private(set) var hasEventsPermission = false
    private(set) var hasRemindersPermission = false

    init() {}

    // MARK: - Permissions

    func requestEventsPermission() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            hasEventsPermission = granted
            return granted
        } catch {
            hasEventsPermission = false
            return false
        }
    }

    func requestRemindersPermission() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            hasRemindersPermission = granted
            return granted
        } catch {
            hasRemindersPermission = false
            return false
        }
    }

    // MARK: - Events (read)

    func fetchEvents(daysAhead: Int = 7) async -> [CalendarEvent] {
        guard hasEventsPermission else { return [] }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.convert)
    }

    // MARK: - Events (write)

    /// Creates a new event in the default calendar. Returns the event id
    /// (useful for undo / modification later).
    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        notes: String? = nil
    ) throws -> String {
        guard hasEventsPermission else {
            throw CalendarError.notAuthorized
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.location = location
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    // MARK: - Reminders (read)

    func fetchIncompleteReminders() async -> [Reminder] {
        guard hasRemindersPermission else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        return await withCheckedContinuation { (cont: CheckedContinuation<[Reminder], Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: (reminders ?? []).map(Self.convert))
            }
        }
    }

    // MARK: - Reminders (write)

    /// Creates a reminder in the default reminders list. Returns id.
    @discardableResult
    func createReminder(
        title: String,
        dueDate: Date? = nil,
        notes: String? = nil
    ) throws -> String {
        guard hasRemindersPermission else {
            throw CalendarError.notAuthorized
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        }
        reminder.calendar = store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func completeReminder(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw CalendarError.notFound
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    // MARK: - Conversion

    private static func convert(_ e: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: e.eventIdentifier,
            title: e.title ?? "(untitled)",
            startDate: e.startDate,
            endDate: e.endDate,
            location: e.location,
            notes: e.notes,
            isAllDay: e.isAllDay
        )
    }

    private static func convert(_ r: EKReminder) -> Reminder {
        let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return Reminder(
            id: r.calendarItemIdentifier,
            title: r.title ?? "(untitled)",
            dueDate: due,
            isCompleted: r.isCompleted,
            notes: r.notes
        )
    }
}

enum CalendarError: Error, LocalizedError {
    case notAuthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Calendar or Reminders access was denied."
        case .notFound: "That calendar item no longer exists."
        }
    }
}
