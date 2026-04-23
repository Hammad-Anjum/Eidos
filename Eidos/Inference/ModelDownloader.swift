import Foundation

@MainActor
@Observable
final class ModelDownloader {

    enum Phase: Sendable, Equatable {
        case idle
        case downloading  // fetching weights from HuggingFace
        case loading      // MLX is memory-mapping + initialising the model
        case ready
        case failed(String)
    }

    var progress: Double = 0
    var phase: Phase = .idle
    var error: String?

    // Back-compat for callers that only care "is something happening".
    var isDownloading: Bool {
        switch phase {
        case .downloading, .loading: true
        default: false
        }
    }

    private let gemma: GemmaSession
    private let downloader = HuggingFaceDownloader()

    init(gemma: GemmaSession) {
        self.gemma = gemma
    }

    var selectedVariant: GemmaVariant {
        get {
            GemmaVariant(rawValue: UserDefaults.standard.string(forKey: "eidos.variant") ?? "")
                ?? .defaultForDevice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "eidos.variant")
        }
    }

    var isModelDownloaded: Bool {
        // Simulator has no real MLX — `GemmaSession.load()` is a mock that
        // just flips `isLoaded = true`. Downloading multi-GB weights into
        // a sim that can't use them is wasted bandwidth, so we short-
        // circuit the gate here and let the app go straight to RootView.
        // On device this is a genuine check against UserDefaults.
        #if targetEnvironment(simulator)
        return true
        #else
        return UserDefaults.standard.bool(forKey: "eidos.modelDownloaded")
        #endif
    }
}

extension ModelDownloader.Phase {
    var errorMessage: String? {
        if case .failed(let msg) = self { return msg }
        return nil
    }
}

@MainActor
extension ModelDownloader {

    /// Downloads the model files to `Documents/<variant>/` then loads them.
    /// EgressGuard is opened for HuggingFace hosts during the download.
    func download(variant: GemmaVariant) async {
        guard !isDownloading else { return }

        // B7: disk space preflight
        if let freeBytes = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           freeBytes < variant.approximateDiskBytes {
            phase = .failed("Not enough storage. Need ~\(variant.approximateDiskBytes / 1_000_000_000) GB free.")
            error = phase.errorMessage
            return
        }

        phase = .downloading
        error = nil
        progress = 0
        selectedVariant = variant

        EgressGuard.isModelDownloadInProgress = true
        defer { EgressGuard.isModelDownloadInProgress = false }

        do {
            let directory = try GemmaSession.modelDirectory(for: variant)
            try await downloader.download(
                repoID: variant.huggingFaceID,
                to: directory,
                onProgress: { [weak self] p in
                    Task { @MainActor in
                        guard let self else { return }
                        let prevBucket = Int(self.progress * 1000)
                        self.progress = p
                        let nowBucket = Int(p * 1000)
                        #if DEBUG
                        if nowBucket > prevBucket {
                            // Fires every 0.1% — shows visible movement even on
                            // the huge model.safetensors download.
                            print("[Eidos] Download \(String(format: "%.1f", p * 100))%")
                        }
                        #endif
                    }
                }
            )

            // Downloads done — MLX now mmaps and initialises the model.
            // This can take 10-30s for multi-GB weights; surface it so
            // users don't think the app is frozen.
            phase = .loading
            try await gemma.load(variant: variant, config: ModelConfig(variant: variant))
            UserDefaults.standard.set(true, forKey: "eidos.modelDownloaded")
            phase = .ready
        } catch {
            let msg = UserFacingError.message(for: error)
            self.error = msg
            phase = .failed(msg)
        }
    }
}
