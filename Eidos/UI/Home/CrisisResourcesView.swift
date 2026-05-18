import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Curated emergency resources surface, presented when the user taps
/// the "I need help now" tile on Home.
///
/// **Why this exists outside SafetyGate**: `SafetyGate.evaluate(...)`
/// matches specific crisis phrases (suicide, medical emergency, etc.)
/// inside chat input. The Home tile can't predict which crisis the
/// user is in — they may be in panic, dissociation, RSD spiral, an
/// active medical event, etc. So this view presents ALL the
/// resources at once with one-tap dial / text and lets the user
/// pick the right line themselves.
///
/// Design notes:
/// - **Calm, not alarming.** Muted red tile on Home → muted-ish red
///   header here. We don't fluoresce; we acknowledge.
/// - **One tap per resource.** Each row dials/texts/opens the URL
///   directly. No confirmation dialogs, no "are you sure" — the
///   user came here because they need help, not friction.
/// - **No data leaves the device.** Tapping a row uses `tel:` / `sms:`
///   / `https:` URL schemes — iOS handles the actual call/text via
///   the system, NOT through Eidos. We never know whether the user
///   tapped or completed any of these.
/// - **A "just need grounding" out** at the bottom, in case the user
///   tapped the tile but their actual need is the (non-crisis)
///   grounding script. Routes to the existing Ground flow.
struct CrisisResourcesView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    primaryResources
                    secondaryResources
                    groundingEscape
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("Help now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close this screen")
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You reached out.")
                .font(.title2.weight(.semibold))
            Text("These are real people, trained for this. None of these go through Eidos — your phone dials or texts them directly.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var primaryResources: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("If your life feels at risk")

            CrisisRow(
                icon: "phone.fill",
                title: "Call 988",
                subtitle: "Suicide & Crisis Lifeline (US, 24/7)",
                tint: .red,
                action: { open("tel:988") }
            )
            CrisisRow(
                icon: "message.fill",
                title: "Text HOME to 741741",
                subtitle: "Crisis Text Line (US / Canada)",
                tint: .red,
                action: { open("sms:741741&body=HOME") }
            )
            CrisisRow(
                icon: "globe.americas.fill",
                title: "findahelpline.com",
                subtitle: "Global directory by country",
                tint: .red,
                action: { open("https://findahelpline.com") }
            )
        }
    }

    private var secondaryResources: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("If it's a medical emergency")

            CrisisRow(
                icon: "phone.fill",
                title: "Call 911",
                subtitle: "US / Canada emergency services",
                tint: .orange,
                action: { open("tel:911") }
            )
            CrisisRow(
                icon: "phone.fill",
                title: "Call 112",
                subtitle: "EU / UK / India emergency services",
                tint: .orange,
                action: { open("tel:112") }
            )

            sectionTitle("Other lines")
                .padding(.top, 6)

            CrisisRow(
                icon: "phone.fill",
                title: "Childhelp 1-800-422-4453",
                subtitle: "Child abuse hotline (US)",
                tint: .blue,
                action: { open("tel:1-800-422-4453") }
            )
            CrisisRow(
                icon: "phone.fill",
                title: "Poison Control 1-800-222-1222",
                subtitle: "US poison emergency",
                tint: .blue,
                action: { open("tel:1-800-222-1222") }
            )
        }
    }

    private var groundingEscape: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("If you just need grounding")

            Button {
                container.pendingChatLaunch = ChatLaunchIntent(
                    prompt: "I'm spiraling. Help me ground.",
                    autoSend: true
                )
                NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.pink, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Just talk me down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Eidos runs a grounding script — sensory cue, breath, one physical action.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.pink.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Just talk me down")
            .accessibilityHint("Switches to the Chat tab and runs the grounding script. Does not call anyone.")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Open helper

    /// Routes a URL via UIApplication. tel: and sms: schemes are
    /// system-handled — Eidos doesn't see the dial / text payload.
    private func open(_ urlString: String) {
        #if canImport(UIKit)
        guard let url = URL(string: urlString) else { return }
        // Log only the SCHEME, never the body or destination, so the
        // diagnostics log stays free of phone numbers (which would
        // partially defeat the zero-egress story if exfiltrated via
        // crash reports). `tel`/`sms`/`https` is enough to debug.
        EidosLogger.shared.log(.info, category: .ui,
            event: "crisis.resource.open",
            payload: ["scheme": url.scheme ?? "unknown"])
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Row component

private struct CrisisRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(tint.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}
