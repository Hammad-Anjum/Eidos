import SwiftUI

struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @State private var step = 0
    @State private var selectedVariant: GemmaVariant = .defaultForDevice

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0: welcomeStep
            case 1: variantStep
            default: downloadStep
            }
        }
        .animation(.default, value: step)
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
            Text("Your private, on-device AI assistant.\nNo data ever leaves your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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
            Button("Download") { step = 2 }
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
