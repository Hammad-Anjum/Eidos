import Foundation

// Skills that reach into other apps. Each builds an `AppAction`, queues
// it on the registry, and returns a short confirmation-ready message.
// The actual URL opens only after the user taps Confirm in the UI.

// MARK: - Messaging

struct SendWhatsAppSkill: Skill {
    let name = "send_whatsapp"
    let description = "Compose a WhatsApp message. The user will see a confirmation before anything is sent."
    let parametersSchema = #"{"type":"object","properties":{"phone":{"type":"string","description":"E.164 phone number, e.g. +14155551212"},"text":{"type":"string"}},"required":["phone","text"]}"#

    private let registry: AppActionRegistry

    init(registry: AppActionRegistry) { self.registry = registry }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let phone = parameters["phone"]?.stringValue, !phone.isEmpty else {
            return .failure("Missing required parameter: phone")
        }
        guard let text = parameters["text"]?.stringValue, !text.isEmpty else {
            return .failure("Missing required parameter: text")
        }
        let action = AppAction.whatsapp(phone: phone, text: text)
        await MainActor.run(resultType: Void.self) { registry.enqueue(action) }
        return .success("WhatsApp message drafted — awaiting your confirmation.")
    }
}

struct SendSMSSkill: Skill {
    let name = "send_sms"
    let description = "Compose an SMS. The user will see a confirmation before anything is sent."
    let parametersSchema = #"{"type":"object","properties":{"phone":{"type":"string"},"body":{"type":"string"}},"required":["phone","body"]}"#

    private let registry: AppActionRegistry

    init(registry: AppActionRegistry) { self.registry = registry }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let phone = parameters["phone"]?.stringValue, !phone.isEmpty else {
            return .failure("Missing required parameter: phone")
        }
        guard let body = parameters["body"]?.stringValue, !body.isEmpty else {
            return .failure("Missing required parameter: body")
        }
        let action = AppAction.sms(phone: phone, body: body)
        await MainActor.run(resultType: Void.self) { registry.enqueue(action) }
        return .success("SMS drafted — awaiting your confirmation.")
    }
}

struct SendEmailSkill: Skill {
    let name = "send_email"
    let description = "Compose an email. The user will see a confirmation before Mail opens."
    let parametersSchema = #"{"type":"object","properties":{"to":{"type":"string"},"subject":{"type":"string"},"body":{"type":"string"}},"required":["to"]}"#

    private let registry: AppActionRegistry

    init(registry: AppActionRegistry) { self.registry = registry }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let to = parameters["to"]?.stringValue, !to.isEmpty else {
            return .failure("Missing required parameter: to")
        }
        let action = AppAction.email(
            to: to,
            subject: parameters["subject"]?.stringValue,
            body: parameters["body"]?.stringValue
        )
        await MainActor.run(resultType: Void.self) { registry.enqueue(action) }
        return .success("Email drafted — awaiting your confirmation.")
    }
}

// MARK: - Voice

struct PlaceCallSkill: Skill {
    let name = "place_call"
    let description = "Initiate a phone call. The user confirms before the dialer opens."
    let parametersSchema = #"{"type":"object","properties":{"phone":{"type":"string"}},"required":["phone"]}"#

    private let registry: AppActionRegistry

    init(registry: AppActionRegistry) { self.registry = registry }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let phone = parameters["phone"]?.stringValue, !phone.isEmpty else {
            return .failure("Missing required parameter: phone")
        }
        let action = AppAction.phoneCall(phone: phone)
        await MainActor.run(resultType: Void.self) { registry.enqueue(action) }
        return .success("Call prepared — awaiting your confirmation.")
    }
}

// MARK: - Navigation

struct NavigateSkill: Skill {
    let name = "navigate"
    let description = "Open Maps with directions to a destination."
    let parametersSchema = #"{"type":"object","properties":{"destination":{"type":"string"},"transport":{"type":"string","enum":["driving","walking","transit"],"default":"driving"}},"required":["destination"]}"#

    private let registry: AppActionRegistry

    init(registry: AppActionRegistry) { self.registry = registry }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let destination = parameters["destination"]?.stringValue, !destination.isEmpty else {
            return .failure("Missing required parameter: destination")
        }
        let transport: AppAction.MapsTransport = {
            switch parameters["transport"]?.stringValue {
            case "walking": return .walking
            case "transit": return .transit
            default:        return .driving
            }
        }()
        let action = AppAction.mapsNavigate(destination: destination, transport: transport)
        await MainActor.run(resultType: Void.self) { registry.enqueue(action) }
        return .success("Route prepared — awaiting your confirmation.")
    }
}

struct RequestRideSkill: Skill {
    let name = "request_ride"
    let description = "Open Uber with a destination pre-filled. The user approves and completes the booking in the Uber app."
    let parametersSchema = #"{"type":"object","properties":{"destination":{"type":"string"}},"required":["destination"]}"#

    private let registry: AppActionRegistry

    init(registry: AppActionRegistry) { self.registry = registry }

    func invoke(parameters: [String: AnyCodable]) async -> SkillResult {
        guard let destination = parameters["destination"]?.stringValue, !destination.isEmpty else {
            return .failure("Missing required parameter: destination")
        }
        let action = AppAction.rideRequest(destination: destination)
        await MainActor.run(resultType: Void.self) { registry.enqueue(action) }
        return .success("Ride draft prepared — awaiting your confirmation.")
    }
}
