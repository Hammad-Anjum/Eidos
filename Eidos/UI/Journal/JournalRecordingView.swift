import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen voice-journal recording surface.
///
/// Flow:
/// 1. View appears → asynchronously requests speech + mic permission.
/// 2. User taps "Tap to start" → `SpeechTranscriber.start()` opens the
///    mic and streams partial transcripts into `transcriber.transcript`.
/// 3. User taps "Tap to stop" → `transcriber.stop()` settles the
///    transcript. The captured text is wrapped in a `ToolCall(tool:
///    "voice_journal_capture", parameters: ["transcript": ...])` and
///    dispatched via `container.skillRegistry`. This bypasses Gemma
///    entirely — the journal save is a deterministic memory write.
/// 4. `SpeechSynthesizer.shared.speak("Saved.")` confirms by voice.
/// 5. `onComplete(true)` fires; caller dismisses the cover.
///
/// Cancel button bails without persisting anything.
///
/// Design notes for AuDHD audience:
/// - Whole-screen dark background, single big action button. No
///   secondary affordances competing for attention.
/// - Tap-to-start / tap-to-stop (per user decision May 12): a single
///   tap target, no sustained motor input required. 5-minute
///   safety auto-stop is a v2 stretch goal.
/// - Voice-confirmation on save means the user doesn't have to look
///   at the screen during the flow — they can be lying down,
///   eyes-closed, mid-burnout.
struct JournalRecordingView: View {

    @Environment(AppContainer.self) private var container

    @State private var transcriber = SpeechTranscriber()
    @State private var phase: Phase = .idle
    @State private var permissionDenied = false

    /// Called when the flow finishes. `true` if the journal saved;
    /// `false` if the user cancelled before saving.
    let onComplete: (Bool) -> Void

    private enum Phase: Equatable {
        case idle              // permission granted, ready to start
        case requestingPermission
        case recording
        case saving
        case done
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                cancelBar
                Spacer(minLength: 12)
                micIconView
                Text(stateLabel)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                transcriptView
                Spacer()
                actionButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .preferredColorScheme(.dark)
        .task { await requestPermissionIfNeeded() }
    }

    // MARK: - Sub-views

    private var cancelBar: some View {
        HStack {
            Button {
                cancel()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .accessibilityLabel("Cancel journal recording without saving")
            Spacer()
        }
    }

    private var micIconView: some View {
        Image(systemName: micIcon)
            .font(.system(size: 96, weight: .semibold))
            .foregroundStyle(micColor)
            .symbolEffect(.pulse, options: .repeating, isActive: phase == .recording)
            .frame(height: 130)
            .accessibilityHidden(true)
    }

    private var transcriptView: some View {
        ScrollView {
            Text(transcriptDisplay)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .frame(maxHeight: 180)
        .accessibilityLabel("Transcript")
        .accessibilityValue(transcriber.transcript.isEmpty ? "Empty" : transcriber.transcript)
    }

    private var actionButton: some View {
        Button(action: tapAction) {
            Text(actionLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(actionColor, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: actionColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionLabel)
        .accessibilityHint(actionHint)
        .accessibilityAddTraits(.isButton)
        .disabled(actionDisabled)
    }

    // MARK: - State derivations

    private var micIcon: String {
        switch phase {
        case .idle, .requestingPermission: return "mic.fill"
        case .recording: return "waveform.circle.fill"
        case .saving: return "tray.and.arrow.down.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var micColor: Color {
        switch phase {
        case .recording: return .red
        case .done: return .green
        default: return .white
        }
    }

    private var stateLabel: String {
        if permissionDenied { return "Mic or speech permission denied" }
        switch phase {
        case .idle:                  return "Ready"
        case .requestingPermission:  return "Asking for permission..."
        case .recording:             return "Listening"
        case .saving:                return "Saving..."
        case .done:                  return "Saved"
        }
    }

    private var actionLabel: String {
        if permissionDenied { return "Open Settings" }
        switch phase {
        case .idle:                  return "Tap to start"
        case .requestingPermission:  return "..."
        case .recording:             return "Tap to stop"
        case .saving:                return "Saving..."
        case .done:                  return "Done"
        }
    }

    private var actionHint: String {
        switch phase {
        case .idle:      return "Begins recording. Speak freely."
        case .recording: return "Stops recording and saves the transcript to memory."
        default:         return ""
        }
    }

    private var actionColor: Color {
        switch phase {
        case .recording: return .red
        case .done:      return .green
        default:         return .purple
        }
    }

    private var actionDisabled: Bool {
        if permissionDenied { return false }   // tap routes to Settings
        return phase == .saving || phase == .requestingPermission
    }

    private var transcriptDisplay: String {
        if transcriber.transcript.isEmpty {
            switch phase {
            case .recording: return "(listening...)"
            case .idle, .requestingPermission: return "(tap to start when ready)"
            default: return " "
            }
        }
        return transcriber.transcript
    }

    // MARK: - Actions

    private func tapAction() {
        if permissionDenied {
            openSettings()
            return
        }
        switch phase {
        case .idle:      startRecording()
        case .recording: stopAndSave()
        default:         break
        }
    }

    private func cancel() {
        if phase == .recording { transcriber.stop() }
        onComplete(false)
    }

    private func requestPermissionIfNeeded() async {
        phase = .requestingPermission
        let granted = await transcriber.requestPermission()
        permissionDenied = !granted
        phase = .idle
    }

    private func startRecording() {
        do {
            try transcriber.start()
            phase = .recording
        } catch {
            EidosLogger.shared.error(.skill,
                event: "journal.record.start.failed",
                error: error, failure: .skillExecute)
            permissionDenied = true
        }
    }

    private func stopAndSave() {
        transcriber.stop()
        let captured = transcriber.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .saving

        // `@MainActor in` is required: `JournalRecordingView` is a SwiftUI
        // struct View (not implicitly main-actor isolated under Swift 6
        // strict concurrency), and the Task body mutates `phase` (@State)
        // + calls `onComplete`. Without the annotation the mutations can
        // race the SwiftUI re-render loop.
        Task { @MainActor in
            // Empty transcript — common when the user taps stop too
            // quickly. Bail without dispatching to skill; cancel-style.
            guard !captured.isEmpty else {
                phase = .done
                try? await Task.sleep(nanoseconds: 600_000_000)
                onComplete(false)
                return
            }

            let call = ToolCall(
                tool: "voice_journal_capture",
                parameters: [
                    "transcript": AnyCodable(captured),
                    "topics": AnyCodable([AnyCodable]()),
                ]
            )
            let result = await container.skillRegistry.dispatch(call)

            phase = .done

            if !result.isError {
                SpeechSynthesizer.shared.speak("Saved.", languageCode: "en-US")
            } else {
                EidosLogger.shared.log(.warn, category: .skill,
                    event: "journal.save.skill-error",
                    message: result.content)
            }

            try? await Task.sleep(nanoseconds: 900_000_000)
            onComplete(!result.isError)
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
