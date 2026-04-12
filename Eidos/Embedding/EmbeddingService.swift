import Foundation
import NaturalLanguage
import Accelerate

// Per plan.md §A3 / §A3-asset, Eidos uses Apple's built-in
// `NLContextualEmbedding` for sentence embeddings. No CoreML, no bundled
// weights, no WordPiece tokenizer — it all lives inside the Natural
// Language framework and runs on the Neural Engine.
//
// The model returns one vector per token. This wrapper mean-pools those
// token vectors into a single sentence-level vector and L2-normalises so
// that a dot-product in VectorStore is cosine similarity.
//
// First-launch flow (see §A3-asset): `ensureAssetsAvailable()` runs during
// onboarding BEFORE `EgressGuard.install()` arms the network allowlist,
// because `requestEmbeddingAssets()` fetches weights from Apple's CDN.
// On subsequent launches, `hasAvailableAssets` is already true and no
// network call is needed.

enum EmbeddingError: Error, LocalizedError {
    case modelUnavailable(language: String)
    case notLoaded
    case assetDownloadFailed(String)
    case emptyInput
    case embeddingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let lang):
            return "No on-device contextual embedding model is available for \(lang)."
        case .notLoaded:
            return "Embedding service is not loaded."
        case .assetDownloadFailed(let msg):
            return "Failed to download the embedding asset: \(msg)"
        case .emptyInput:
            return "Cannot embed empty text."
        case .embeddingFailed(let msg):
            return "Embedding failed: \(msg)"
        }
    }
}

actor EmbeddingService {

    private var embedding: NLContextualEmbedding?
    private(set) var isLoaded = false
    private(set) var dimensions: Int = 0
    private(set) var language: NLLanguage = .english

    init() {}

    // MARK: - Lifecycle

    /// Returns true if the on-device asset for the target language is already
    /// cached. If false, the caller must run `ensureAssetsAvailable()` while
    /// network access is still permitted (i.e. before EgressGuard is armed).
    func hasAssets(for language: NLLanguage = .english) -> Bool {
        NLContextualEmbedding(language: language)?.hasAvailableAssets ?? false
    }

    /// Downloads the NLContextualEmbedding asset from Apple's CDN if it is
    /// not already present. Must be called before `EgressGuard.install()`
    /// — see plan.md §A3-asset.
    func ensureAssetsAvailable(for language: NLLanguage = .english) async throws {
        guard let emb = NLContextualEmbedding(language: language) else {
            throw EmbeddingError.modelUnavailable(language: language.rawValue)
        }
        guard !emb.hasAvailableAssets else { return }
        do {
            try await emb.requestEmbeddingAssets()
        } catch {
            throw EmbeddingError.assetDownloadFailed(error.localizedDescription)
        }
    }

    /// Loads the embedding model into memory. Assumes assets are already
    /// present (i.e. `ensureAssetsAvailable()` has already succeeded at
    /// least once on this device, or the asset was cached).
    func load(language: NLLanguage = .english) async throws {
        guard let emb = NLContextualEmbedding(language: language) else {
            throw EmbeddingError.modelUnavailable(language: language.rawValue)
        }
        guard emb.hasAvailableAssets else {
            // Assets missing and EgressGuard is almost certainly armed at this
            // point — surface the problem instead of silently trying to hit
            // the network and getting blocked.
            throw EmbeddingError.notLoaded
        }
        do {
            try emb.load()
        } catch {
            throw EmbeddingError.embeddingFailed(error.localizedDescription)
        }
        self.embedding = emb
        self.dimensions = emb.dimension
        self.language = language
        self.isLoaded = true
    }

    // MARK: - Embedding

    /// Returns an L2-normalised sentence embedding for the given text.
    /// Token vectors are mean-pooled and normalised so cosine similarity
    /// equals the dot product — matching what `VectorStore` expects.
    func embed(_ text: String) async throws -> [Float] {
        guard let embedding, isLoaded else { throw EmbeddingError.notLoaded }

        let cleaned = preprocess(text)
        guard !cleaned.isEmpty else { throw EmbeddingError.emptyInput }

        let result: NLContextualEmbeddingResult
        do {
            result = try embedding.embeddingResult(for: cleaned, language: language)
        } catch {
            throw EmbeddingError.embeddingFailed(error.localizedDescription)
        }

        let pooled = meanPool(result: result, dimensions: dimensions, text: cleaned)
        guard !pooled.isEmpty else { throw EmbeddingError.embeddingFailed("no tokens produced") }
        return l2Normalise(pooled)
    }

    // MARK: - Private

    private func preprocess(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep a generous character cap — the model handles sub-word
        // tokenisation itself, but very long strings waste Neural Engine time.
        return String(trimmed.prefix(2000))
    }

    /// Mean-pools all per-token vectors from an embedding result into a
    /// single dense vector.
    private func meanPool(
        result: NLContextualEmbeddingResult,
        dimensions: Int,
        text: String
    ) -> [Float] {
        guard dimensions > 0 else { return [] }
        var accumulator = [Float](repeating: 0, count: dimensions)
        var tokenCount = 0

        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            if vector.count == dimensions {
                for i in 0..<dimensions {
                    accumulator[i] += Float(vector[i])
                }
                tokenCount += 1
            }
            return true
        }

        guard tokenCount > 0 else { return [] }
        var divisor = Float(tokenCount)
        vDSP_vsdiv(accumulator, 1, &divisor, &accumulator, 1, vDSP_Length(dimensions))
        return accumulator
    }

    private func l2Normalise(_ v: [Float]) -> [Float] {
        var sumOfSquares: Float = 0
        vDSP_svesq(v, 1, &sumOfSquares, vDSP_Length(v.count))
        var norm = sqrtf(sumOfSquares)
        guard norm > 0 else { return v }
        var result = [Float](repeating: 0, count: v.count)
        vDSP_vsdiv(v, 1, &norm, &result, 1, vDSP_Length(v.count))
        return result
    }
}
