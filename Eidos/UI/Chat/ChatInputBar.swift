import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    let isGenerating: Bool
    let onSend: () -> Void

    @State private var transcriber = SpeechTranscriber()

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            micButton

            ZStack(alignment: .topLeading) {
                if text.isEmpty && !transcriber.isRecording {
                    Text("Message Eidos")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                }
                TextField("", text: $text, axis: .vertical)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .lineLimit(1...6)
                    .disabled(isGenerating || transcriber.isRecording)
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1.5)
            )

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .onChange(of: transcriber.transcript) { _, newValue in
            if transcriber.isRecording { text = newValue }
        }
    }

    // MARK: - Mic

    private var micButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            Image(systemName: transcriber.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(transcriber.isRecording ? Color.red : Color.accentColor.opacity(0.9))
                .symbolEffect(.pulse, options: .repeating, isActive: transcriber.isRecording)
        }
        .disabled(isGenerating)
        .frame(width: 44, height: 44)
        .accessibilityLabel(transcriber.isRecording ? "Stop recording" : "Start voice input")
    }

    // MARK: - Send

    private var sendButton: some View {
        Button(action: onSend) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: canSend
                                ? [.accentColor, Color.accentColor.opacity(0.8)]
                                : [Color.secondary.opacity(0.3), Color.secondary.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .disabled(!canSend)
        .accessibilityLabel("Send")
    }

    private var canSend: Bool {
        !text.isEmpty && !isGenerating && !transcriber.isRecording
    }

    private func toggleRecording() async {
        if transcriber.isRecording {
            transcriber.stop()
            return
        }
        let ok = await transcriber.requestPermission()
        guard ok else { return }
        do { try transcriber.start() }
        catch { /* surfaced via transcriber.error */ }
    }
}
