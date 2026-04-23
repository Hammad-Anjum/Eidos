import SwiftUI

struct ModelDownloadView: View {
    @Environment(AppContainer.self) private var container
    let variant: GemmaVariant

    var body: some View {
        let dl = container.modelDownloader
        VStack(spacing: 20) {
            Spacer()
            phaseView(dl)
            Spacer()
        }
        .padding()
        .task {
            if case .idle = dl.phase, !dl.isModelDownloaded {
                await dl.download(variant: variant)
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
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.title2.bold())
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
