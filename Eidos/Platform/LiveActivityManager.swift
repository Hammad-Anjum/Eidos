import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
@preconcurrency import ActivityKit
#endif

/// Ownership of Eidos's Live Activities. Two kinds are multiplexed:
/// - a "generating briefing" pulse while Gemma streams
/// - a "meeting soon" countdown 0-15 min before a calendar event
///
/// Only one activity of each kind lives at a time; starting a second
/// of the same kind replaces the first.
actor LiveActivityManager {

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
    private var generatingActivity: Activity<DigestActivityAttributes>?
    private var meetingActivity: Activity<DigestActivityAttributes>?
    #endif

    // MARK: - Generating briefing

    func startGenerating() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = DigestActivityAttributes.ContentState(
            phase: .generating,
            title: "Generating briefing",
            detail: "Eidos is thinking…",
            symbolName: "sparkles"
        )
        do {
            generatingActivity = try Activity.request(
                attributes: DigestActivityAttributes(kind: "eidos"),
                content: .init(state: state, staleDate: Date().addingTimeInterval(120))
            )
        } catch {
            EidosLogger.shared.error(.ui, event: "live_activity.generating.start_failed",
                error: error, failure: .unknown)
        }
        #endif
    }

    func updateGenerating(preview: String) async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
        guard let activity = generatingActivity else { return }
        let state = DigestActivityAttributes.ContentState(
            phase: .generating,
            title: "Generating briefing",
            detail: String(preview.suffix(80)),
            symbolName: "sparkles"
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        await activity.update(content)
        #endif
    }

    func endGenerating(finalText: String?) async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
        guard let activity = generatingActivity else { return }
        generatingActivity = nil
        let state = DigestActivityAttributes.ContentState(
            phase: .generating,
            title: "Briefing ready",
            detail: finalText.map { String($0.prefix(80)) } ?? "",
            symbolName: "checkmark.circle.fill"
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(8)))
        #endif
    }

    // MARK: - Meeting soon

    func startMeetingCountdown(title: String, startsAt: Date) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Meeting activity is single-slot; caller should end previous
        // ones via `endMeetingCountdown()` if needed.
        let state = DigestActivityAttributes.ContentState(
            phase: .meetingSoon,
            title: title,
            detail: "Starting soon",
            startsAt: startsAt,
            symbolName: "calendar"
        )
        do {
            meetingActivity = try Activity.request(
                attributes: DigestActivityAttributes(kind: "eidos"),
                content: .init(state: state, staleDate: startsAt.addingTimeInterval(300))
            )
        } catch {
            EidosLogger.shared.error(.ui, event: "live_activity.meeting.start_failed",
                error: error, failure: .unknown)
        }
        #endif
    }

    func endMeetingCountdown() async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst) && os(iOS)
        guard let activity = meetingActivity else { return }
        meetingActivity = nil
        let current = activity.content.state
        let state = DigestActivityAttributes.ContentState(
            phase: .meetingSoon,
            title: current.title,
            detail: "Started",
            startsAt: current.startsAt,
            symbolName: "calendar"
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        #endif
    }
}
