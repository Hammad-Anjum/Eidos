import SwiftUI

/// One chat bubble. Assistant bubbles get a small speaker button
/// trailing the message so the user can re-speak the content aloud
/// via `SpeechSynthesizer.shared`.
///
/// The speaker is an explicit, on-demand affordance — independent of
/// the `EidosFeatureFlags.shared.speakRepliesEnabled` global toggle
/// which controls *automatic* speak-on-receive. Even with auto-speak
/// off, the user can always tap to re-read. This mirrors Be My AI's
/// most-used button per r/Blind community feedback.
struct MessageBubble: View {
    let role: String
    let content: String

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            Group {
                if isUser {
                    Text(content)
                } else {
                    MarkdownText(markdown: content)
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isUser {
                speakerButton
                Spacer(minLength: 32)
            }
        }
    }

    /// Re-speak the bubble's content via `SpeechSynthesizer`.
    /// Voice-locale derived from the user's preferred device language;
    /// premium voice is selected automatically if installed.
    @ViewBuilder
    private var speakerButton: some View {
        // Hide on empty / mid-stream bubbles so a tap doesn't speak
        // partial content. The bubble itself still renders so the
        // streaming text animation is unaffected; only the button is
        // gated.
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Button {
                let lang = Locale.preferredLanguages.first ?? "en-US"
                SpeechSynthesizer.shared.cancel()
                SpeechSynthesizer.shared.speak(trimmed, languageCode: lang)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            // Per ChatInputBar 44pt-min rationale: a 32pt visual icon
            // with a contentShape Rectangle is widened to ~44pt of
            // tappable area without ballooning the visual size.
            .contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Speak this reply aloud")
            .accessibilityHint("Reads the message above using on-device text-to-speech.")
        }
    }
}
