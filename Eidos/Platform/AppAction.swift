import Foundation

/// A prepared, cross-app action. The model "composes" an `AppAction`
/// (via a skill); the UI surfaces a confirmation; on approval the system
/// opens the target app with the payload pre-filled. The user always
/// gets the last word — this is how iOS keeps cross-app control
/// consent-based.
enum AppAction: Equatable, Sendable, Identifiable {

    case whatsapp(phone: String, text: String)
    case sms(phone: String, body: String)
    case email(to: String, subject: String?, body: String?)
    case phoneCall(phone: String)
    case mapsNavigate(destination: String, transport: MapsTransport)
    case rideRequest(destination: String)   // Uber deep-link
    case facetime(identifier: String)

    enum MapsTransport: String, Sendable {
        case driving   = "d"
        case walking   = "w"
        case transit   = "r"   // Apple Maps calls public transit "r"
    }

    // MARK: - Identity

    var id: String { url?.absoluteString ?? String(describing: self) }

    // MARK: - URL

    var url: URL? {
        switch self {
        case .whatsapp(let phone, let text):
            var c = URLComponents(string: "whatsapp://send")!
            c.queryItems = [
                URLQueryItem(name: "phone", value: Self.cleanPhone(phone)),
                URLQueryItem(name: "text", value: text),
            ]
            return c.url

        case .sms(let phone, let body):
            // SMS uses `;` to separate body — but `sms:` + querystring is
            // more reliable across iOS versions.
            var c = URLComponents()
            c.scheme = "sms"
            c.path = Self.cleanPhone(phone)
            c.queryItems = [URLQueryItem(name: "body", value: body)]
            return c.url

        case .email(let to, let subject, let body):
            var c = URLComponents()
            c.scheme = "mailto"
            c.path = to
            var items: [URLQueryItem] = []
            if let subject { items.append(URLQueryItem(name: "subject", value: subject)) }
            if let body { items.append(URLQueryItem(name: "body", value: body)) }
            if !items.isEmpty { c.queryItems = items }
            return c.url

        case .phoneCall(let phone):
            return URL(string: "tel:\(Self.cleanPhone(phone))")

        case .mapsNavigate(let destination, let transport):
            var c = URLComponents(string: "maps://")!
            c.queryItems = [
                URLQueryItem(name: "daddr", value: destination),
                URLQueryItem(name: "dirflg", value: transport.rawValue),
            ]
            return c.url

        case .rideRequest(let destination):
            var c = URLComponents(string: "uber://")!
            c.queryItems = [
                URLQueryItem(name: "action", value: "setPickup"),
                URLQueryItem(name: "pickup", value: "my_location"),
                URLQueryItem(name: "dropoff[formatted_address]", value: destination),
            ]
            return c.url

        case .facetime(let identifier):
            return URL(string: "facetime://\(identifier)")
        }
    }

    // MARK: - Human-readable description

    /// Used on the confirmation sheet. Never includes secrets (we build
    /// from fields the user gave us, but phone numbers are partially
    /// masked to avoid surprise leaks if screenshots happen).
    var confirmationTitle: String {
        switch self {
        case .whatsapp(let phone, _):        "Send WhatsApp to \(Self.maskPhone(phone))"
        case .sms(let phone, _):             "Send SMS to \(Self.maskPhone(phone))"
        case .email(let to, _, _):           "Open Mail to \(to)"
        case .phoneCall(let phone):          "Call \(Self.maskPhone(phone))"
        case .mapsNavigate(let destination, _): "Open Maps — directions to \(destination)"
        case .rideRequest(let destination):  "Request an Uber to \(destination)"
        case .facetime(let identifier):      "FaceTime \(identifier)"
        }
    }

    var confirmationBody: String? {
        switch self {
        case .whatsapp(_, let text):         text
        case .sms(_, let body):              body
        case .email(_, let subject, let body):
            [subject, body].compactMap { $0 }.joined(separator: "\n\n").ifNonEmpty
        default: nil
        }
    }

    /// SF Symbol for the confirmation UI.
    var systemImage: String {
        switch self {
        case .whatsapp:        "bubble.left.and.bubble.right.fill"
        case .sms:             "message.fill"
        case .email:           "envelope.fill"
        case .phoneCall:       "phone.fill"
        case .mapsNavigate:    "map.fill"
        case .rideRequest:     "car.fill"
        case .facetime:        "video.fill"
        }
    }

    // MARK: - Scheme (used for `canOpenURL` / Info.plist allowlist)

    var scheme: String { url?.scheme ?? "" }

    // MARK: - Normalisation helpers

    static func cleanPhone(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }

    static func maskPhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 4 else { return phone }
        let suffix = digits.suffix(4)
        return "••••\(suffix)"
    }
}

// MARK: - tiny helpers

private extension String {
    var ifNonEmpty: String? { isEmpty ? nil : self }
}
