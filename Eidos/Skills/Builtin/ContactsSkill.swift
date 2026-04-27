import Foundation

struct ContactsSkill: Skill {
    let name = "search_contacts"
    let description = "Look up a contact by name. Returns name, email, and phone number."
    let parametersSchema = #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#

    private let source: ContactsSource

    init(source: ContactsSource) {
        self.source = source
    }

    func availability() async -> SkillAvailability {
        await source.hasPermission
            ? .available
            : .permissionDenied(message: "Contacts access not granted. Settings > Privacy & Security > Contacts > Eidos.")
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let query = parameters["query"]?.stringValue, !query.isEmpty else {
            return .failure("Missing required parameter: query")
        }
        let results = await source.search(query: query, limit: 5)
        if results.isEmpty {
            return .success("No contacts match '\(query)'.")
        }
        let lines = results.map { contact -> String in
            var line = "• \(contact.displayName)"
            if let org = contact.organization { line += " (\(org))" }
            if let email = contact.emails.first { line += " · \(email)" }
            if let phone = contact.phones.first { line += " · \(phone)" }
            return line
        }
        return .success(lines.joined(separator: "\n"))
    }
}
