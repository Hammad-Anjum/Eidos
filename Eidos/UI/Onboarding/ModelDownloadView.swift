import SwiftUI

struct ModelDownloadView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 24) {
            Text("Download Gemma 4")
                .font(.title.bold())
            Text("This is a ~3 GB one-time download. It runs entirely on your device after this.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ProgressView(value: container.modelDownloader.progress)
                .padding(.horizontal, 32)

            Button("Start download") {
                Task { await container.modelDownloader.download(variant: .e4b) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(container.modelDownloader.isDownloading)
        }
        .padding()
    }
}
