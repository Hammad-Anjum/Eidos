import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen body-doubling surface — the AuADHD hackathon differentiator.
///
/// Two phases:
///
/// 1. **Setup.** The user names the task (optional text field), picks a
///    duration (5/10/15/25 min), and taps "Sit with me." This dispatches
///    `start_body_double` once, which writes a session memory and returns
///    the canonical opening line.
///
/// 2. **Session.** The view owns the clock and the audio cues — no
///    further Gemma round-trips. A breath dot pulses slowly (4-2-6 in /
///    hold / out). At 50% elapsed, the synthesizer speaks one
///    check-in line. At 100% it speaks the closing line. The user can
///    end early with a single tap; the dismissal is silent.
///
/// Design rules:
/// - **No coaching, no questions.** The audio cues are statements, never
///   "how's it going" or "want another." Presence, not interrogation.
/// - **One thing on screen.** Setup has the input + duration pills.
///   Session has only the clock and the breath dot. Nothing competes.
/// - **Tappable end at all times.** AuDHD users abandon sessions they
///   can't exit; making the exit explicit + immediate is the trust
///   floor for the feature working at all.
struct BodyDoublingView: View {

    @Environment(AppContainer.self) private var container

    let onComplete: () -> Void

    @State private var phase: Phase = .setup
    @State private var taskText: String = ""
    @State private var durationMinutes: Int
    @State private var remainingSeconds: Int = 600
    @State private var totalSeconds: Int = 600
    @State private var halfwayAnnounced: Bool = false
    @State private var ticker: Timer?

    /// Initial duration mirrors the user's current energy band so the
    /// view opens to a default that respects their capacity *right
    /// now* — not whichever number the previous session happened to
    /// end on. The user can still override via the duration pills;
    /// the energy-derived default is just a thoughtful starting point.
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let energy = UserDefaults.standard
            .object(forKey: "eidos.auadhd.energyLevel") as? Int ?? 2
        _durationMinutes = State(initialValue: Self.defaultDuration(for: energy))
    }

    /// Energy → default session length.
    ///   - 0-1 (burnout/low): 5 min — protects against over-commitment
    ///     when initiating anything at all is the win.
    ///   - 2-3 (okay/good): 10 min — the canonical body-double slot.
    ///   - 4 (high): 25 min — pomodoro-equivalent, suitable for a
    ///     real chunk of work.
    /// Returned value MUST be one of `durationOptions` so the matching
    /// pill highlights correctly without a fallback render glitch.
    static func defaultDuration(for energy: Int) -> Int {
        switch max(0, min(4, energy)) {
        case 0, 1: return 5
        case 2, 3: return 10
        default:   return 25
        }
    }
    /// Cycles 0 → 1 → 0 over a slow breath rhythm. Drives the dot
    /// scale + opacity in the session view. Animated via SwiftUI's
    /// implicit animation on phase changes.
    @State private var breathOpen: Bool = false

    private enum Phase: Equatable {
        case setup
        case session
        case done
    }

    private static let durationOptions: [Int] = [5, 10, 15, 25]

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            switch phase {
            case .setup:   setupContent
            case .session: sessionContent
            case .done:    doneContent
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { stopTicker() }
    }

    // MARK: - Background

    /// Calm gradient that shifts slightly with the chosen duration.
    /// Indigo at rest; the session phase deepens to near-black so the
    /// clock dominates and ambient distractions fade.
    private var background: LinearGradient {
        let colors: [Color] = phase == .session
            ? [Color(red: 0.04, green: 0.04, blue: 0.10),
               Color(red: 0.10, green: 0.05, blue: 0.18)]
            : [Color(red: 0.10, green: 0.07, blue: 0.20),
               Color(red: 0.15, green: 0.10, blue: 0.25)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Setup phase

    private var setupContent: some View {
        VStack(spacing: 28) {
            cancelBar
            Spacer(minLength: 8)

            VStack(spacing: 14) {
                Image(systemName: "person.line.dotted.person.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Sit with me")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Eidos sits with you while you start. No coaching, no questions.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What are you doing?  (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                TextField(
                    "",
                    text: $taskText,
                    prompt: Text("e.g. fold the laundry")
                        .foregroundStyle(.white.opacity(0.35))
                )
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Optional — what you're working on")
            }
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 10) {
                Text("How long?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 28)
                HStack(spacing: 10) {
                    ForEach(Self.durationOptions, id: \.self) { mins in
                        durationPill(mins)
                    }
                }
                .padding(.horizontal, 28)
            }

            Spacer()

            Button(action: startSession) {
                Text("Sit with me")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.45, green: 0.25, blue: 0.85),
                                     Color(red: 0.30, green: 0.18, blue: 0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22)
                    )
                    .shadow(color: .purple.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .accessibilityLabel("Start a \(durationMinutes) minute session")
            .accessibilityHint("Eidos starts a quiet timer and checks in once at the halfway mark.")

            Spacer(minLength: 16)
        }
    }

    private func durationPill(_ mins: Int) -> some View {
        let selected = (durationMinutes == mins)
        return Button {
            durationMinutes = mins
        } label: {
            Text("\(mins)m")
                .font(.callout.weight(.semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected
                        ? Color.purple.opacity(0.85)
                        : Color.white.opacity(0.10),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mins) minutes")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Session phase

    private var sessionContent: some View {
        VStack(spacing: 36) {
            cancelBar(endLabel: "End early")
            Spacer()

            Text(formatClock(remainingSeconds))
                .font(.system(size: 84, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityLabel("\(remainingSeconds / 60) minutes \(remainingSeconds % 60) seconds remaining")

            breathDot

            if !taskText.isEmpty {
                Text("With: \(taskText)")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Extend button — explicit user-initiated, no nag. Adds 5
            // minutes to both `remainingSeconds` and `totalSeconds` so
            // the halfway threshold scales with the new total. If the
            // user extends *after* the halfway announcement already
            // fired, we leave `halfwayAnnounced = true` — re-announcing
            // mid-session would feel surveillant. The end announcement
            // and closing line still fire on the new total.
            extendButton

            Spacer(minLength: 16)
        }
    }

    private var extendButton: some View {
        Button {
            extendSession(by: 5 * 60)
        } label: {
            Label("+5 min", systemImage: "plus.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add five minutes to the session")
        .accessibilityHint("Extends the timer without announcing anything. Useful when you've found your rhythm.")
    }

    /// Slowly pulsing dot — 4s inhale, 2s hold open, 6s exhale.
    /// Animates implicitly off the `breathOpen` state toggle which is
    /// driven by the timer at 12-second intervals.
    private var breathDot: some View {
        Circle()
            .fill(Color.white.opacity(breathOpen ? 0.85 : 0.30))
            .frame(width: breathOpen ? 96 : 44, height: breathOpen ? 96 : 44)
            .blur(radius: breathOpen ? 0 : 2)
            .animation(.easeInOut(duration: breathOpen ? 4 : 6), value: breathOpen)
            .accessibilityHidden(true)
    }

    // MARK: - Done phase

    private var doneContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.green)
            Text("Done. That's it.")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            onComplete()
        }
    }

    // MARK: - Shared chrome

    private var cancelBar: some View { cancelBar(endLabel: "Cancel") }

    private func cancelBar(endLabel: String) -> some View {
        HStack {
            Button {
                endNow(speakClose: false)
            } label: {
                Text(endLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .accessibilityLabel(endLabel)
            .accessibilityHint("Ends the session immediately. Nothing is announced aloud.")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - Actions

    private func startSession() {
        totalSeconds = durationMinutes * 60
        remainingSeconds = totalSeconds
        halfwayAnnounced = false
        phase = .session

        // Dispatch the skill once — writes the session memory and
        // returns the canonical opening line which we speak now.
        Task { @MainActor in
            let call = ToolCall(
                tool: "start_body_double",
                parameters: [
                    "task": AnyCodable(taskText),
                    "duration_minutes": AnyCodable(durationMinutes),
                ]
            )
            let result = await container.skillRegistry.dispatch(call)
            // Speak whatever the skill returned — error or success —
            // so the user gets feedback either way. The skill's
            // canonical success line is "I'm here. Start whenever."
            SpeechSynthesizer.shared.speak(result.content)
        }

        startTicker()
        // Kick off the first breath cycle on the next runloop turn.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            beginBreathCycle()
        }
    }

    /// Drives the timer + halfway/end announcements. One-second tick is
    /// cheap and lets the clock match wall time. Not an
    /// `AsyncSequence` because we want a non-detached MainActor handler
    /// and the `Timer.scheduledTimer` API gives us that for free.
    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Bumps the session timer up by `seconds`. Used by the +5 min
    /// button. Adds the same amount to `totalSeconds` so the halfway
    /// threshold tracks the new total (a 5-minute extension during a
    /// 10-minute session shifts halfway from 5 min → 7m30s elapsed).
    /// Silent — no announcement, no haptic — because the audience
    /// reaches for this button precisely when they don't want to be
    /// pinged out of focus.
    private func extendSession(by seconds: Int) {
        guard phase == .session, seconds > 0 else { return }
        remainingSeconds += seconds
        totalSeconds     += seconds
    }

    private func tick() {
        guard phase == .session else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        // Halfway announcement — once.
        let elapsed = totalSeconds - remainingSeconds
        if !halfwayAnnounced && totalSeconds > 0 && elapsed >= totalSeconds / 2 {
            halfwayAnnounced = true
            let halfwayMinutes = max(1, elapsed / 60)
            SpeechSynthesizer.shared.speak("You're \(halfwayMinutes) minutes in.")
        }
        if remainingSeconds == 0 {
            stopTicker()
            SpeechSynthesizer.shared.speak("Done. That's it.")
            phase = .done
        }
    }

    /// 12-second breath cycle. Toggles `breathOpen` after each in/out
    /// duration so SwiftUI's implicit animation handles the dot scale.
    private func beginBreathCycle() {
        guard phase == .session else { return }
        breathOpen = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard phase == .session else { return }
            // Hold open 2s, then exhale 6s.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard phase == .session else { return }
            breathOpen = false
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard phase == .session else { return }
            beginBreathCycle()
        }
    }

    private func endNow(speakClose: Bool) {
        stopTicker()
        if speakClose {
            SpeechSynthesizer.shared.speak("Done. That's it.")
        } else {
            SpeechSynthesizer.shared.cancel()
        }
        onComplete()
    }

    private func formatClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
