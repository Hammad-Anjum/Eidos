import Foundation

struct RemindersSkill: Skill {
    let name = "get_reminders"
    let description = "Fetch the user's incomplete reminders. Use when the user asks what they need to do or about their tasks."
    let parametersSchema = #"{"type":"object","properties":{}}"#

    private let source: CalendarSource

    init(source: CalendarSource) {
        self.source = source
    }

    func availability() async -> SkillAvailability {
        await source.hasRemindersPermission
            ? .available
            : .permissionDenied(message: "Reminders access not granted. Settings > Privacy & Security > Reminders > Eidos.")
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        let reminders = await source.fetchIncompleteReminders()
        if reminders.isEmpty {
            return .success("No incomplete reminders.")
        }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEE d MMM, h:mm a"
        let lines = reminders.prefix(20).map { reminder -> String in
            if let due = reminder.dueDate {
                return "• \(reminder.title) (due \(dateFmt.string(from: due)))"
            }
            return "• \(reminder.title)"
        }
        return .success(lines.joined(separator: "\n"))
    }
}

struct CreateReminderSkill: Skill {
    let name = "create_reminder"
    let description = "Create a new reminder. Use when the user says \"remind me to…\". Dates should be ISO-8601 (e.g. 2026-04-22T15:00:00Z) — omit for no due date."
    let parametersSchema = #"{"type":"object","properties":{"title":{"type":"string"},"due_date":{"type":"string"},"notes":{"type":"string"}},"required":["title"]}"#

    private let source: CalendarSource

    init(source: CalendarSource) {
        self.source = source
    }

    func availability() async -> SkillAvailability {
        await source.hasRemindersPermission
            ? .available
            : .permissionDenied(message: "Reminders access not granted. Settings > Privacy & Security > Reminders > Eidos.")
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let title = parameters["title"]?.stringValue, !title.isEmpty else {
            return .failure("Missing required parameter: title")
        }
        let notes = parameters["notes"]?.stringValue
        let dueDate = parameters["due_date"]?.stringValue
            .flatMap { ISO8601DateFormatter().date(from: $0) }

        do {
            _ = try await source.createReminder(title: title, dueDate: dueDate, notes: notes)
            if let due = dueDate {
                let fmt = DateFormatter()
                fmt.dateFormat = "EEE d MMM, h:mm a"
                return .success("Reminder created: \(title) (due \(fmt.string(from: due))).")
            }
            return .success("Reminder created: \(title).")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
