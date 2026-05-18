import SwiftUI

struct ModelDownloadView: View {
    @Environment(AppContainer.self) private var container
    let variant: GemmaVariant
    let forceDownload: Bool

    init(variant: GemmaVariant, forceDownload: Bool = false) {
        self.variant = variant
        self.forceDownload = forceDownload
    }

    var body: some View {
        let dl = container.modelDownloader
        VStack(spacing: 20) {
            Spacer()
            phaseView(dl)
            Spacer()
        }
        .padding()
        .task {
            if case .idle = dl.phase {
                if forceDownload {
                    dl.clearDownloadedModelState(removeFiles: true, variant: variant)
                    await dl.download(variant: variant)
                } else if !dl.isModelDownloaded {
                    await dl.download(variant: variant)
                }
            }
        }
    }

    @ViewBuilder
    private func phaseView(_ dl: ModelDownloader) -> some View {
        switch dl.phase {
        case .idle:
            ProgressView("Starting download…")

        case .downloading:
            VStack(spacing: 14) {
                Text("Downloading \(variant.displayName)")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                ProgressView(value: dl.progress)
                    .padding(.horizontal, 32)
                Text("\(Int(dl.progress * 100))%  ·  \(estimate(variant, progress: dl.progress))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("This is a one-time download. Everything runs on your device after this.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }

        case .loading:
            // Critical: tell the user something's happening, not just a
            // spinner. MLX taking 15-30 seconds to memory-map a 3 GB+
            // model looks like a hang otherwise.
            VStack(spacing: 14) {
                Image(systemName: "cpu")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Loading model into memory…")
                    .font(.title3.bold())
                Text("This takes 15–30 seconds the first time.\nPlease don't quit the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

        case .ready:
            VStack(spacing: 16) {
                if #available(iOS 18.0, *) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    // `.symbolEffect(.bounce)` plays once by default on
                    // iOS 17; the `options: .nonRepeating` variant added
                    // a conformance that only lands in iOS 18, and would
                    // break our iOS 17 deployment target.
                        .symbolEffect(.bounce)
                } else {
                    // Fallback on earlier versions
                }
                Text("Ready")
                    .font(.title2.bold())
                Text("Gemma 4 is loaded and running on your device. Everything from here is local.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Explicit continue button. The app also auto-transitions via
                // `EidosApp`'s gate (it observes `phase`), but users like an
                // explicit hand-off — and in the rare case the auto-transition
                // hasn't fired yet, this gives them a way out.
                Button {
                    container.modelDownloader.markModelReady()
                } label: {
                    Label("Start using Eidos", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }

        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Download failed")
                    .font(.title3.bold())
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") {
                    Task { await container.modelDownloader.download(variant: variant) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Rough downloaded-GB / total-GB label to give users a sense of scale.
    private func estimate(_ variant: GemmaVariant, progress: Double) -> String {
        let total = Double(variant.approximateDiskBytes) / 1_000_000_000
        let done = total * progress
        return String(format: "%.1f / %.1f GB", done, total)
    }
}
