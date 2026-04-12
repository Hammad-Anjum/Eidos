import Foundation

@MainActor
@Observable
final class ModelDownloader {

    var progress: Double = 0
    var isDownloading = false
    var error: String?

    static let modelsDirectory: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
    }()

    init() {}

    func modelPath(for variant: GemmaVariant) -> URL? {
        let url = Self.modelsDirectory.appendingPathComponent(variant.rawValue)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads the selected Gemma variant. Phase 2 implementation fills in:
    ///   - disk-space preflight (B7)
    ///   - SHA256 verification against GemmaVariant.expectedSHA256 (B7)
    ///   - streaming 1 MB buffered write (architecture.md §5.4)
    ///   - EgressGuard-gated URLSession (B14)
    func download(variant: GemmaVariant) async {
        // TODO(phase 2)
    }
}
