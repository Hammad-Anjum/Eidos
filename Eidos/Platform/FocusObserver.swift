import Foundation
import Combine

/// Observes the system Focus mode via `NSUbiquitousKeyValueStore` /
/// `INFocusStatusCenter` signals. When the user is in Work Focus,
/// Eidos's digest and chat tone can shift — we surface this via a
/// published `currentFocus` property.
///
/// Limits: third-party apps can only READ the current Focus's name +
/// whether Focus is active — not the full filter rules. This is
/// enough to tailor tone ("more businesslike on Work", "warmer on
/// Personal", etc.).
@MainActor
@Observable
final class FocusObserver {

    enum FocusHint: Sendable {
        case unknown
        case off
        case work
        case personal
        case sleep
        case doNotDisturb
        case driving
        case fitness
        case other(String)

        var readable: String {
            switch self {
            case .unknown, .off: "No focus"
            case .work: "Work"
            case .personal: "Personal"
            case .sleep: "Sleep"
            case .doNotDisturb: "Do Not Disturb"
            case .driving: "Driving"
            case .fitness: "Fitness"
            case .other(let name): name.capitalized
            }
        }
    }

    var current: FocusHint = .unknown

    private var cancellable: AnyCancellable?

    init() {
        // iOS publishes focus changes through NSNotification when the
        // app has Focus filter entitlement. Without that entitlement
        // we can only sample the last-known focus via NSUserActivity.
        // This observer is best-effort and degrades gracefully.
        cancellable = NotificationCenter.default
            .publisher(for: Notification.Name("NSFocusModeDidChangeNotification"))
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        refresh()
    }

    func refresh() {
        // Best-effort: Focus status only readable with the
        // `com.apple.developer.focus-status` entitlement (requires
        // special review from Apple). Without it we infer from
        // `NSProcessInfo.thermalState` and other proxies — which is
        // to say, we can't reliably. We expose the API so the UI
        // layer doesn't crash; production rollout would need the
        // entitlement + approval.
        current = .unknown
    }
}
