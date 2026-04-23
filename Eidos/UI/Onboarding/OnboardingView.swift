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
        }
        .padding()
    }

    private var variantStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Choose Your Model")
                .font(.title.bold())
            Text("A one-time download. Everything runs on your device after this.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            ForEach(GemmaVariant.allCases, id: \.self) { variant in
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
        ModelDownloadView(variant: selectedVariant)
    }
}
