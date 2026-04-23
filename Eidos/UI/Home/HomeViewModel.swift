import Foundation
import WidgetKit

@MainActor
@Observable
final class HomeViewModel {
    var digest: String = ""
    var signals: ProactiveSignals?
    var isGeneratingDigest = false
    var errorMessage: String?

    private let generator: ProactiveDigestGenerator
    private let calendarSource: CalendarSource
    private let healthSource: HealthSource
    private let notificationScheduler: NotificationScheduler?
    private let liveActivityManager: LiveActivityManager?

    init(
        generator: ProactiveDigestGenerator,
        calendarSource: CalendarSource,
        healthSource: HealthSource,
        notificationScheduler: NotificationScheduler? = nil,
        liveActivityManager: LiveActivityManager? = nil
    ) {
        self.generator = generator
        self.calendarSource = calendarSource
        self.healthSource = healthSource
        self.notificationScheduler = notificationScheduler
        self.liveActivityManager = liveActivityManager
    }

    /// Requests any missing permissions, then runs a full digest (signals
    /// + narration). Signals render immediately; the paragraph fills in
    /// when Gemma finishes.
    func refresh() async {
        guard !isGeneratingDigest else { return }
        isGeneratingDigest = true
        digest = ""
        errorMessage = nil

        _ = await calendarSource.requestEventsPermission()
        _ = await calendarSource.requestRemindersPermission()
        // Health is optional — don't block refresh on denial.
        _ = await healthSource.requestPermission()

        // Show cards as soon as signals are ready, even before Gemma replies.
        signals = await generator.signalsOnly()

        // Start Live Activity so the Dynamic Island pulses while Gemma thinks.
        await liveActivityManager?.startGenerating()

        do {
            let snapshot = try await generator.generate()
            digest = snapshot.briefingText
            signals = snapshot.signals
            await liveActivityManager?.endGenerating(finalText: snapshot.briefingText)
            // Re-schedule the morning notification with THIS digest baked
            // into the body, so tomorrow's Lock Screen shows the briefing
            // directly — one less reason to open the app.
            if let notificationScheduler, notificationScheduler.digestEnabled {
                await notificationScheduler.scheduleMorningDigest(preview: snapshot.briefingText)
            }
            // Push to the widget via the App Group container.
            Self.publishWidgetSnapshot(from: snapshot)
        } catch {
            errorMessage = error.localizedDescription
            await liveActivityManager?.endGenerating(finalText: nil)
        }
        isGeneratingDigest = false
    }

    // MARK: - Widget bridge

    /// Translates a `DigestSnapshot` into the tiny `WidgetDigestSnapshot`
    /// the widget renders, writes it to the shared App Group container,
    /// and asks WidgetKit to refresh all timelines.
    nonisolated private static func publishWidgetSnapshot(from snapshot: DigestSnapshot) {
        let greeting: String = {
            let h = Calendar.current.component(.hour, from: Date())
            switch h {
            case 5..<12:  return "Good morning"
            case 12..<17: return "Good afternoon"
            case 17..<22: return "Good evening"
            default:      return "Hello"
            }
        }()

        let nextEvent: WidgetDigestSnapshot.EventSummary?
        if let first = snapshot.signals.todayEvents.first {
            nextEvent = .init(title: first.title, start: first.startDate, location: first.location)
        } else if let upcoming = snapshot.signals.upcomingEvents.first {
            nextEvent = .init(title: upcoming.title, start: upcoming.startDate, location: upcoming.location)
        } else {
            nextEvent = nil
        }

        let widgetSnapshot = WidgetDigestSnapshot(
            greeting: greeting,
            briefing: snapshot.briefingText,
            nextEvent: nextEvent,
            eventsToday: snapshot.signals.todayEvents.count,
            remindersOpen: snapshot.signals.openReminders.count
        )
        SharedStore.writeDigest(widgetSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
