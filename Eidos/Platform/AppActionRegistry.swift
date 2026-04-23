import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Queue of `AppAction`s waiting for user confirmation. Skills push to
/// it; the chat UI observes and shows a confirmation sheet. On approval,
/// `execute(_:)` hands off to `UIApplication.open(_:)` — the target app
/// launches with the payload pre-filled, and the user presses Send
/// themselves.
@MainActor
@Observable
final class AppActionRegistry {

    /// Actions awaiting confirmation, oldest first.
    var pending: [AppAction] = []

    /// The most recent action the user approved — useful for telemetry
    /// or undo prompts in the UI.
    private(set) var lastExecuted: AppAction?

    // MARK: - Enqueue

    @discardableResult
    func enqueue(_ action: AppAction) -> AppAction {
        pending.append(action)
        return action
    }

    /// Removes an action from the queue without executing it.
    func dismiss(_ action: AppAction) {
        pending.removeAll { $0 == action }
    }

    // MARK: - Execute

    /// Asks the OS to open the URL for `action`. Returns `true` if the
    /// OS accepted the request; the user still needs to tap Send in the
    /// target app.
    @discardableResult
    func execute(_ action: AppAction) async -> Bool {
        guard let url = action.url else { return false }
        dismiss(action)
        #if canImport(UIKit)
        let opened = await UIApplication.shared.open(url)
        if opened { lastExecuted = action }
        return opened
        #else
        lastExecuted = action
        return false
        #endif
    }

    /// Cheap check — is the target app installed and willing to receive
    /// the scheme? `canOpenURL` requires the scheme to be declared in
    /// `LSApplicationQueriesSchemes` in Info.plist; schemes not listed
    /// always return false regardless of whether the app is installed.
    func canOpen(_ action: AppAction) -> Bool {
        guard let url = action.url else { return false }
        #if canImport(UIKit)
        return UIApplication.shared.canOpenURL(url)
        #else
        return true
        #endif
    }
}
