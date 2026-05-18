import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// UIKit app-delegate bridge for the SwiftUI app.
///
/// Sole purpose today: post a notification at the earliest possible
/// moment when the app is about to lose foreground focus, so the
/// privacy-snapshot overlay in `EidosApp.body` can render BEFORE iOS
/// captures the app-switcher thumbnail.
///
/// SwiftUI's `scenePhase = .inactive` transition fires at roughly the
/// same moment as `applicationWillResignActive`, but on slower
/// devices the SwiftUI render queue can land its frame AFTER iOS has
/// already grabbed the snapshot. By hooking the UIKit delegate
/// callback directly, we get the synchronous notification that fires
/// before the snapshot — closing the race window.
///
/// This file carries no app logic, no state, no observation: pure
/// timing bridge. Keep it that way. Any logic added here drifts
/// outside the `@MainActor @Observable` DI graph that the rest of
/// the app uses.
final class EidosAppDelegate: NSObject {

    #if canImport(UIKit)
    // The UIApplicationDelegate methods below are conditionally
    // exposed only on platforms that have UIKit. The class itself
    // stays compilable on macOS-only Mac Catalyst tests because the
    // NSObject conformance is unconditional.
    //
    // UIApplicationDelegate conformance is declared in the
    // UIKit-only extension below to keep the NSObject base callable
    // from non-UIKit targets if any are ever added.
    #endif
}

#if canImport(UIKit)
extension EidosAppDelegate: UIApplicationDelegate {

    /// Fires immediately as the app is about to lose active state —
    /// before iOS captures the app-switcher snapshot. We post a
    /// notification that `EidosApp.body` observes to flip
    /// `isObscured = true` synchronously on the main runloop.
    func applicationWillResignActive(_ application: UIApplication) {
        NotificationCenter.default.post(
            name: .eidosWillResignActive,
            object: nil
        )
    }

    /// Fires when the app regains active state. Counterpart to the
    /// `willResignActive` notification — drops the overlay.
    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationCenter.default.post(
            name: .eidosDidBecomeActive,
            object: nil
        )
    }
}
#endif

extension Notification.Name {
    /// Posted from `EidosAppDelegate.applicationWillResignActive`.
    /// Subscribers should flip into a privacy-preserving state
    /// (overlay on, sensitive views hidden) synchronously — the OS
    /// snapshot fires immediately after.
    static let eidosWillResignActive = Notification.Name("eidos.willResignActive")

    /// Posted from `EidosAppDelegate.applicationDidBecomeActive`.
    /// Subscribers should restore normal UI.
    static let eidosDidBecomeActive = Notification.Name("eidos.didBecomeActive")
}
