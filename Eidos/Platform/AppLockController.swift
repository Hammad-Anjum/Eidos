import Foundation
import LocalAuthentication
import SwiftUI

/// Biometric / passcode gate for the entire app.
///
/// Eidos is a privacy-first product. Anyone who picks up an unlocked
/// phone should NOT be able to read the user's chats, memories, or
/// crystallized facts without authenticating again. This controller
/// drives a full-screen lock view that requires FaceID / TouchID /
/// device passcode before the main UI is shown.
///
/// Trigger conditions:
///   - First app launch in a session (`scenePhase` transitions
///     `.background` -> `.active` after a cold start).
///   - Returning from background after more than `unlockGraceWindow`
///     seconds (5 minutes by default — short enough to actually
///     protect, long enough to not be annoying for quick app
///     switching).
///
/// User toggle: `EidosFeatureFlags.appLockEnabled` (defaults ON in
/// release builds). If the device has neither biometrics nor a
/// passcode, the lock is bypassed (you can't authenticate without
/// either, and falsely insisting would brick the app).
@MainActor
@Observable
final class AppLockController {

    /// Whether the lock is currently presented. Drives a `.fullScreenCover`
    /// in `EidosApp`.
    private(set) var isLocked: Bool = false

    /// Last time the user successfully authenticated (or app launched
    /// with the lock disabled). Used by `enterBackground()` to decide
    /// whether the next foreground crossing should re-lock.
    private var lastUnlockedAt: Date = .distantPast

    /// How long Eidos can be backgrounded before the next foreground
    /// requires a fresh unlock.
    private let unlockGraceWindow: TimeInterval = 5 * 60  // 5 minutes

    /// Latest authentication-attempt error message, surfaced in the
    /// lock UI. Cleared on success.
    private(set) var lastErrorMessage: String?

    /// Whether the device can actually authenticate the user. False
    /// means no biometrics AND no passcode — in that case, locking
    /// is impossible and we silently bypass.
    var canAuthenticate: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &error
        )
    }

    /// Called from `EidosApp.init()` after `installCrashBreadcrumbs()`.
    /// On a cold start with the lock enabled, presents the lock
    /// immediately so the underlying UI never renders before
    /// authentication.
    func bootstrapLockState() {
        guard EidosFeatureFlags.shared.appLockEnabled else {
            isLocked = false
            return
        }
        guard canAuthenticate else {
            // No biometrics + no passcode: device-level security has
            // been disabled by the user, we can't be more strict than
            // the OS. Bypass and log so the inconsistency is visible
            // in Diagnostics.
            EidosLogger.shared.log(.warn, category: .app,
                event: "applock.bypassed.no-auth-method-available")
            isLocked = false
            return
        }
        isLocked = true
        EidosLogger.shared.log(.info, category: .app,
            event: "applock.cold-start.locked")
    }

    /// Called from the `scenePhase` observer when the app foregrounds
    /// after having been backgrounded. Re-locks if we crossed the
    /// grace window.
    func handleForegroundTransition() {
        guard EidosFeatureFlags.shared.appLockEnabled else { return }
        guard canAuthenticate else { return }
        let elapsed = Date().timeIntervalSince(lastUnlockedAt)
        if elapsed > unlockGraceWindow {
            isLocked = true
            EidosLogger.shared.log(.info, category: .app,
                event: "applock.foreground.re-locked",
                payload: ["elapsed_s": Int(elapsed)])
        }
    }

    /// Called from the `scenePhase` observer when the app
    /// backgrounds. We don't lock immediately on background (avoids
    /// flicker during the snapshot capture moment) — the
    /// `PrivacySnapshotOverlay` covers content during snapshot, and
    /// the next foreground will check the grace window.
    func handleBackgroundTransition() {
        // No-op for now. The grace-window check on
        // `handleForegroundTransition` is what enforces re-locking.
    }

    /// Triggers the LocalAuthentication prompt. On success, drops the
    /// lock and stamps `lastUnlockedAt`. On failure, the lock UI
    /// shows `lastErrorMessage` and stays presented.
    func authenticate() async {
        let context = LAContext()
        context.localizedReason = "Authenticate to access Eidos"
        // Allow biometrics OR passcode — we never want to be more
        // restrictive than the device-owner auth chain.
        let policy: LAPolicy = .deviceOwnerAuthentication
        do {
            let success = try await context.evaluatePolicy(
                policy, localizedReason: "Authenticate to access Eidos")
            if success {
                lastUnlockedAt = .init()
                lastErrorMessage = nil
                isLocked = false
                EidosLogger.shared.log(.info, category: .app,
                    event: "applock.authenticated")
            } else {
                lastErrorMessage = "Authentication did not succeed."
            }
        } catch let error as LAError {
            lastErrorMessage = Self.message(for: error)
            EidosLogger.shared.error(.app, event: "applock.authenticate.failed",
                error: error, failure: .permissionDenied)
        } catch {
            lastErrorMessage = error.localizedDescription
            EidosLogger.shared.error(.app, event: "applock.authenticate.failed",
                error: error, failure: .permissionDenied)
        }
    }

    /// Maps `LAError` codes to user-readable messages.
    private static func message(for error: LAError) -> String {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Cancelled."
        case .authenticationFailed:
            return "FaceID / passcode did not match. Try again."
        case .userFallback:
            return "Use device passcode."
        case .biometryLockout:
            return "Biometric authentication is locked. Use device passcode."
        case .passcodeNotSet:
            return "Set a device passcode in Settings to use Eidos."
        default:
            return error.localizedDescription
        }
    }
}
