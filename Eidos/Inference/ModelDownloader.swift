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

    private enum Keys {
        static let modelDownloaded = "eidos.modelDownloaded"
        static let selectedVariant = "eidos.variant"
        static let testerFreshDownloadMarker = "eidos.testerFreshDownloadMarker"
    }

    /// Release-only tester reset. The marker now incorporates **the build
    /// version + bundle version**, so every Release build automatically
    /// bumps the marker without us having to remember to edit a string.
    /// Any update over any prior install fires the fresh-download path.
    ///
    /// This closes the AltStore in-place-update bug where stale UserDefaults
    /// preserved an old marker and skipped the reset on a new IPA install.
    private static var currentTesterFreshDownloadMarker: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "fresh.\(short).\(build)"
    }

    init(gemma: GemmaSession) {
        self.gemma = gemma
    }

    var selectedVariant: GemmaVariant {
        get {
            let stored = GemmaVariant(rawValue: UserDefaults.standard.string(forKey: Keys.selectedVariant) ?? "")
                ?? .defaultForDevice
            return stored.isAvailableOnThisDevice ? stored : .defaultForDevice
        }
        set {
            let safeVariant = newValue.isAvailableOnThisDevice ? newValue : .defaultForDevice
            UserDefaults.standard.set(safeVariant.rawValue, forKey: Keys.selectedVariant)
        }
    }

    var isModelDownloaded: Bool {
        // Simulator has no real MLX — `GemmaSession.load()` is a mock that
        // just flips `isLoaded = true`. Downloading multi-GB weights into
        // a sim that can't use them is wasted bandwidth, so we short-
        // circuit the gate here and let the app go straight to RootView.
        // On device this verifies both the persisted flag and required
        // files. A stale flag must never bypass onboarding into chat.
        #if targetEnvironment(simulator)
        return true
        #else
        guard UserDefaults.standard.bool(forKey: Keys.modelDownloaded) else {
            return false
        }
        guard Self.hasRequiredModelFiles(for: selectedVariant) else {
            UserDefaults.standard.set(false, forKey: Keys.modelDownloaded)
            return false
        }
        return true
        #endif
    }

    nonisolated static func hasRequiredModelFiles(for variant: GemmaVariant) -> Bool {
        guard let directory = try? GemmaSession.modelDirectory(for: variant) else {
            return false
        }
        return hasRequiredModelFiles(in: directory)
    }

    nonisolated static func hasRequiredModelFiles(in directory: URL) -> Bool {
        missingRequiredModelFiles(in: directory).isEmpty
    }

    nonisolated static func missingRequiredModelFiles(in directory: URL) -> [String] {
        let expectedSafetensorsBytes = expectedModelSafetensorsBytes(in: directory)
        return HuggingFaceDownloader.gemma4Files
            .filter(\.required)
            .compactMap { file in
                let url = directory.appendingPathComponent(file.name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? NSNumber,
                      size.int64Value > 0 else {
                    return file.name
                }
                if file.name == "model.safetensors",
                   let expectedSafetensorsBytes,
                   size.int64Value < expectedSafetensorsBytes {
                    return file.name
                }
                return nil
            }
    }

    private nonisolated static func expectedModelSafetensorsBytes(in directory: URL) -> Int64? {
        let indexURL = directory.appendingPathComponent("model.safetensors.index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = object["metadata"] as? [String: Any],
              let totalSize = metadata["total_size"] as? NSNumber else {
            return nil
        }
        return totalSize.int64Value
    }

    func beginCachedModelLoad() {
        error = nil
        progress = 1
        phase = .loading
    }

    func markModelReady() {
        UserDefaults.standard.set(true, forKey: Keys.modelDownloaded)
        progress = 1
        error = nil
        phase = .ready
    }

    func clearDownloadedModelState(
        message: String? = nil,
        removeFiles: Bool = false,
        variant: GemmaVariant? = nil
    ) {
        UserDefaults.standard.set(false, forKey: Keys.modelDownloaded)
        progress = 0
        error = message
        if removeFiles {
            removeModelFiles(variant: variant)
        }
        phase = message.map { .failed($0) } ?? .idle
    }

    /// Forces a clean model download for external Release tester IPAs.
    ///
    /// This protects against AltStore's update path preserving sandbox
    /// state from a previous broken build. It is intentionally skipped in
    /// DEBUG and simulator builds so development remains fast.
    func resetExternalTesterModelStateIfNeeded() {
        #if DEBUG
        return
        #else
        #if targetEnvironment(simulator)
        return
        #else
        let marker = Self.currentTesterFreshDownloadMarker
        guard UserDefaults.standard.string(forKey: Keys.testerFreshDownloadMarker) != marker else {
            return
        }
        clearDownloadedModelState(removeFiles: true)
        UserDefaults.standard.set(marker, forKey: Keys.testerFreshDownloadMarker)
        EidosLogger.shared.log(
            .warn,
            category: .download,
            event: "tester.force-fresh-model-download",
            payload: ["marker": marker]
        )
        #endif
        #endif
    }

    private func removeModelFiles(variant: GemmaVariant?) {
        let variants = variant.map { [$0] } ?? GemmaVariant.allCases
        for variant in variants {
            guard let directory = try? GemmaSession.modelDirectory(for: variant),
                  FileManager.default.fileExists(atPath: directory.path) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: directory)
                EidosLogger.shared.log(
                    .info,
                    category: .download,
                    event: "model.files.removed",
                    payload: ["variant": variant.rawValue]
                )
            } catch {
                EidosLogger.shared.error(
                    .download,
                    event: "model.files.remove.failed",
                    error: error,
                    failure: .downloadDiskFull,
                    extra: ["variant": variant.rawValue]
                )
            }
        }
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
            let missing = Self.missingRequiredModelFiles(in: directory)
            guard missing.isEmpty else {
                throw HuggingFaceError.missingRequiredFile(missing.joined(separator: ", "))
            }
            try await gemma.load(variant: variant, config: ModelConfig(variant: variant))
            markModelReady()
        } catch {
            let msg = UserFacingError.message(for: error)
            clearDownloadedModelState(message: msg)
        }
    }
}
