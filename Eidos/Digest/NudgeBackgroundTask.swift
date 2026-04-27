import Foundation
// BGTaskScheduler is iOS-only — Mac Catalyst exposes the API but
// silently drops requests, and pure macOS doesn't have it at all.
// We compile the entire scheduling surface only on iOS proper.
#if os(iOS) && !targetEnvironment(macCatalyst)
import BackgroundTasks
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Background-task driver that wakes Eidos up periodically (iOS will
/// pick its own cadence based on usage patterns, typically once or
/// twice a day) to scan stale "active priority" memories and surface
/// nudges as local notifications.
///
/// Concretely: when a user crystallizes a memory like "follow up with
/// Anna about the contract" and 14 days pass without any chat
/// touching that memory, this task fires a notification: "You flagged
/// this 14 days ago and haven't followed up." That's a major piece of
/// the "second brain" UX — the assistant nudging you about your own
/// stated intentions, not just answering when prompted.
///
/// Required `Info.plist` entry (added in `project.yml`):
///
///     BGTaskSchedulerPermittedIdentifiers:
///       - com.hissamuddin.eidos.nudges.daily
///
/// Required capability: Background Modes -> Background processing.
///
/// Lifecycle:
///   1. App launches -> `register()` called from `EidosApp.init()`.
///      iOS records the identifier.
///   2. App enters background -> `scheduleNext()` queues a task to
///      run "no earlier than 4 hours from now" (iOS may delay further
///      based on device usage).
///   3. iOS fires the task -> `handle(_:)` runs (capped at ~30
///      seconds), pulls fresh nudge candidates from
///      `ProactiveDigestGenerator`, schedules notifications, and
///      reschedules the next run before exiting.
@MainActor
enum NudgeBackgroundTask {

    /// Identifier matched against the BGTaskScheduler permitted list
    /// in Info.plist. Exposed publicly so app-bootstrap code can pass
    /// it to `register()` without re-typing.
    static let identifier = "com.hissamuddin.eidos.nudges.daily"

    /// Earliest delay between scheduled runs. iOS treats this as a
    /// hint and may delay further. Four hours strikes a balance
    /// between "we run a few times a day at most" and "iOS doesn't
    /// blacklist us as too aggressive".
    static let minimumScheduleDelay: TimeInterval = 4 * 60 * 60

    /// Registers the background-task handler. MUST be called before
    /// the first scene phase transition or BGTaskScheduler refuses
    /// to fire the task.
    static func register(
        proactive: ProactiveDigestGenerator,
        notifications: NotificationScheduler
    ) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            // BGTaskScheduler hands us a `BGTask` (or one of its
            // subclasses). We cast to `BGProcessingTask` to access
            // its expiration handler.
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await Self.handle(
                    processing,
                    proactive: proactive,
                    notifications: notifications
                )
            }
        }
        EidosLogger.shared.log(.info, category: .app,
            event: "nudges.bg.registered",
            payload: ["identifier": identifier])
        #endif
    }

    /// Queues the next run. Idempotent — calling repeatedly just
    /// updates the requested earliest-fire date.
    static func scheduleNext() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false   // we're 100% local
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumScheduleDelay)
        do {
            try BGTaskScheduler.shared.submit(request)
            EidosLogger.shared.log(.info, category: .app,
                event: "nudges.bg.scheduled",
                payload: ["earliest_in_s": Int(minimumScheduleDelay)])
        } catch {
            // Common failure modes: simulator (BGTaskScheduler is
            // a no-op), background modes capability missing, or
            // identifier not in Info.plist allowlist. Log + move on
            // — don't crash the foreground path on a background
            // scheduling miss.
            EidosLogger.shared.error(.app,
                event: "nudges.bg.schedule-failed",
                error: error, failure: .unknown)
        }
        #endif
    }

    // MARK: - Task body

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private static func handle(
        _ task: BGProcessingTask,
        proactive: ProactiveDigestGenerator,
        notifications: NotificationScheduler
    ) async {
        // Always reschedule first. If the body throws or iOS
        // expires us, we still want the next run queued.
        scheduleNext()

        // Honor expiration: iOS expires processing tasks after
        // ~30 seconds. Wire the handler so cancellation propagates
        // through the async work.
        let cancellable = Task {
            await runOnce(
                proactive: proactive,
                notifications: notifications
            )
        }
        task.expirationHandler = {
            cancellable.cancel()
            EidosLogger.shared.log(.warn, category: .app,
                event: "nudges.bg.expired-by-os")
            task.setTaskCompleted(success: false)
        }
        await cancellable.value
        task.setTaskCompleted(success: true)
    }
    #endif

    /// Single-run entry point. Public so it can be invoked from
    /// Diagnostics ("Run nudge pass now") + unit tests, in addition
    /// to the BGTaskScheduler handler.
    static func runOnce(
        proactive: ProactiveDigestGenerator,
        notifications: NotificationScheduler
    ) async {
        EidosLogger.shared.log(.info, category: .app,
            event: "nudges.run.start")

        // Cheap signals-only path: no Gemma narration, no full
        // digest generation. We just need the Nudge structs.
        let signals = await proactive.signalsOnly()
        let nudges = signals.nudges
        EidosLogger.shared.metric(.app, event: "nudges.run.gathered", values: [
            "count": nudges.count,
        ])

        for nudge in nudges {
            await notifications.scheduleNudge(
                identifier: "eidos.nudge.\(nudge.id)",
                title: nudge.title,
                body: nudge.detail
            )
        }

        EidosLogger.shared.log(.info, category: .app,
            event: "nudges.run.done",
            payload: ["scheduled": nudges.count])
    }
}
