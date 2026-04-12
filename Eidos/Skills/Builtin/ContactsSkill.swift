import Foundation

struct ContactsSkill: Skill {
    let name = "search_contacts"
    let description = "Look up a contact by name. Returns name, email, and phone number."
    let parametersSchema = #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#

    private let source: ContactsSource

    init(source: ContactsSource) {
        self.source = source
    }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        // TODO(phase 4)
        .failure("ContactsSkill not yet implemented")
    }
}
