import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Thin wrapper around `UNUserNotificationCenter` for Eidos's proactive
/// flow: daily morning digest, and ad-hoc nudges (e.g. "You haven't
/// talked to X in 30 days"). All scheduling is local — no push, no
/// server. Apple caps pending local notifications at 64; we keep well
/// under that by using `.limit(...)` on the nudge set.
@MainActor
@Observable
final class NotificationScheduler {

    /// User-configured hour/minute of the day for the morning digest.
    /// Stored in UserDefaults; defaults to 7:00am.
    var digestHour: Int {
        get { UserDefaults.standard.object(forKey: "eidos.digest.hour") as? Int ?? 7 }
        set { UserDefaults.standard.set(newValue, forKey: "eidos.digest.hour") }
    }

    var digestMinute: Int {
        get { UserDefaults.standard.object(forKey: "eidos.digest.minute") as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "eidos.digest.minute") }
    }

    /// Whether the user wants the morning-digest notification at all.
    var digestEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "eidos.digest.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "eidos.digest.enabled") }
    }

    private let morningDigestID = "eidos.morning-digest"
    private let nudgeLimit = 20   // cap ad-hoc nudges to leave headroom under Apple's 64

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        #if canImport(UserNotifications)
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func authorizationStatus() async -> NotificationAuthStatus {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .notDetermined
        #endif
    }

    // MARK: - Morning digest

    /// Schedules (or replaces) the repeating daily digest notification at
    /// the configured hour/minute. No-op when `digestEnabled == false`.
    /// Optional `preview` is embedded in the notification body so the
    /// user can read the briefing straight from Lock Screen.
    func scheduleMorningDigest(preview: String? = nil) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningDigestID])
        guard digestEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.subtitle = "Your Eidos briefing"
        if let preview, !preview.isEmpty {
            // iOS limits notification body length; trim to ~300 chars so
            // it fits the expanded Lock Screen card.
            content.body = Self.truncated(preview, to: 300)
        } else {
            content.body = "Tap to open today's briefing."
        }
        content.sound = .default
        content.threadIdentifier = "eidos.digest"
        content.interruptionLevel = .active

        var components = DateComponents()
        components.hour = digestHour
        components.minute = digestMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: morningDigestID, content: content, trigger: trigger
        )
        try? await center.add(request)
        #endif
    }

    /// Schedules a one-shot nudge notification for stale active-priority
    /// memories. Identifier is supplied by caller so we can dedupe
    /// (e.g. don't queue the same nudge twice if the BG task fires
    /// faster than the user taps it). Skips silently when notification
    /// permission is denied — caller can re-request permission via
    /// `requestPermission()` if it wants the user to be re-prompted.
    func scheduleNudge(identifier: String, title: String, body: String) async {
        #if canImport(UserNotifications)
        let status = await authorizationStatus()
        guard status == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = Self.truncated(body, to: 300)
        content.sound = .default
        content.threadIdentifier = "eidos.nudge"
        content.interruptionLevel = .active

        // Fire immediately (`trigger: nil`). The whole point of a
        // nudge is "right now you have a moment to think about this."
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    /// Deliver the briefing notification immediately (debug / test).
    func deliverNow(title: String = "Eidos briefing", body: String) async {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = Self.truncated(body, to: 300)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "eidos.digest.now.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    private static func truncated(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        let clean = s.replacingOccurrences(of: "\n\n", with: "\n")
        return String(clean.prefix(limit - 1)) + "…"
    }

    // MARK: - Nudges

    /// A one-off nudge: "You told Sarah you'd review the doc by Friday."
    /// Returns `true` if scheduled. Enforces our `nudgeLimit`.
    @discardableResult
    func scheduleNudge(
        id: String,
        title: String,
        body: String,
        fireAt: Date
    ) async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingNudges = pending.filter { $0.identifier.hasPrefix("eidos.nudge.") }
        guard existingNudges.count < nudgeLimit else { return false }
        guard fireAt > Date() else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "eidos.nudge"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "eidos.nudge.\(id)", content: content, trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func cancelNudge(id: String) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["eidos.nudge.\(id)"]
        )
        #endif
    }

    func cancelAll() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        #endif
    }
}

enum NotificationAuthStatus: Sendable {
    case authorized
    case denied
    case notDetermined
}
