import SwiftUI

struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @State private var step = 0
    @State private var selectedVariant: GemmaVariant = .defaultForDevice

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0: welcomeStep
            case 1: privacyStep
            case 2: variantStep
            case 3: IdentityStep(step: $step)
            default: downloadStep
            }
        }
        .animation(.default, value: step)
    }

    /// Onboarding step between Welcome and Variant Select. Three
    /// AuADHD-audience-fit cards that set the product's tone before
    /// the user reaches the model download. Permission-priming work
    /// happens inline when each platform feature is first used (not
    /// batched here — empirically higher grant rates).
    ///
    /// Card refresh (2026-05-13): replaced the generic "Multimodal"
    /// and "Real memory" cards with audience-anchored framing
    /// ("No streaks, no shame", "Two taps to skip everything").
    /// Keeps the privacy commitment as the lead since that's the
    /// genuine moat over cloud-based ADHD/autism apps.
    private var privacyStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("How Eidos is different")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 18) {
                onboardingFeature(
                    icon: "lock.shield.fill",
                    title: "Nothing leaves your phone",
                    body: "Inference, memory, voice — all run on-device. EgressGuard blocks outbound network calls in code. Data brokers buy ADHD and autism diagnoses; we made sure they can't buy yours from us."
                )
                onboardingFeature(
                    icon: "heart.slash.fill",
                    title: "No streaks, no shame",
                    body: "No 'you missed N days,' no virtual pet that dies. The app is here when you reach for it and silent when you don't."
                )
                onboardingFeature(
                    icon: "hand.tap.fill",
                    title: "Two taps to skip everything",
                    body: "Defaults are picked. You can change them in Settings later when you have the executive function. You don't need it now."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 8) {
                Button("Continue") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Next: pick a model + start the one-time download.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private func onboardingFeature(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to Eidos")
                .font(.largeTitle.bold())
            Text("A pocket presence for the days when planning has already failed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 10) {
                Button("Get Started") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                // Audience design rule: never demand executive function.
                // The Skip button lets the user reach the model download
                // (the only un-skippable step — we need the model on
                // disk to run anything) without reading three intro
                // cards first. Variant defaults to E2B on iPhone.
                Button("Skip the tour") { step = 2 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Skips the introduction and goes straight to picking a model.")
            }

            // Tester escape hatch + diagnostic — Release builds only.
            // Lets the tester force-clear all model state if anything
            // weird is happening (eg. the app jumped to Home instead of
            // showing the download screen).
            #if !DEBUG
            VStack(spacing: 6) {
                Text("Build \(Self.buildLabel)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Button("Reset model state & redownload", role: .destructive) {
                    container.modelDownloader.clearDownloadedModelState(removeFiles: true)
                    step = 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 8)
            #endif
        }
        .padding()
    }

    /// Short build label for the welcome diagnostic (Release tester builds).
    /// Format: `1.0 (42)` — short version + bundle build.
    private static var buildLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var variantStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Choose Your Model")
                .font(.title.bold())
            Text("A one-time download. Everything runs on your device after this.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            ForEach(GemmaVariant.selectableCases, id: \.self) { variant in
                Button {
                    selectedVariant = variant
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(variant.displayName)
                                .font(.headline)
                            Text("~\(variant.approximateDiskBytes / 1_000_000_000) GB download")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(variant.onboardingHint)
                                .font(.caption2)
                                .foregroundStyle(variant == .e2b ? .green : .orange)
                        }
                        Spacer()
                        if selectedVariant == variant {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding()
                    .background(selectedVariant == variant ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!variant.isAvailableOnThisDevice)
                .opacity(variant.isAvailableOnThisDevice ? 1 : 0.4)
            }

            Spacer()
            Button("Download") { step = 3 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private var downloadStep: some View {
        ModelDownloadView(variant: selectedVariant, forceDownload: true)
    }
}

private extension GemmaVariant {
    var onboardingHint: String {
        switch self {
        case .e2b:
            "Faster, lower memory — safer first test"
        case .e4b:
            "Smarter, ~5.3 GB — needs an iPhone 15 Pro+ / 8 GB+ RAM"
        }
    }
}
