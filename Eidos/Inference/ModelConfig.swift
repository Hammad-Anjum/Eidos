import Foundation

// Gemma 4 variants hosted by the LiteRT community on Hugging Face.
// Exact file names, sizes, and SHA256 hashes must be verified during Phase 2
// against the live repos. See plan.md §A1.
enum GemmaVariant: String, CaseIterable, Sendable {
    case e2b = "gemma-4-E2B-it-litert-lm.task"
    case e4b = "gemma-4-E4B-it-litert-lm.task"

    var displayName: String {
        switch self {
        case .e2b: return "Gemma 4 E2B (faster, ~1.5 GB)"
        case .e4b: return "Gemma 4 E4B (smarter, ~3 GB)"
        }
    }

    var recommendedFor: String {
        switch self {
        case .e2b: return "iPhone 13 or later"
        case .e4b: return "iPhone 15 Pro or later"
        }
    }

    // TODO(phase 2): Pin exact file names and hashes from huggingface.co/litert-community
    var downloadURL: URL {
        let base = "https://huggingface.co/litert-community"
        switch self {
        case .e2b: return URL(string: "\(base)/gemma-4-E2B-it-litert-lm/resolve/main/\(rawValue)")!
        case .e4b: return URL(string: "\(base)/gemma-4-E4B-it-litert-lm/resolve/main/\(rawValue)")!
        }
    }

    // TODO(phase 2): Fill in the real SHA256 for B7 integrity checking.
    var expectedSHA256: String? {
        nil
    }

    var approximateByteCount: Int64 {
        switch self {
        case .e2b: return 1_500_000_000
        case .e4b: return 3_000_000_000
        }
    }
}

struct ModelConfig: Sendable {
    var variant: GemmaVariant = .e4b
    var maxTokens: Int = 1024
    var temperature: Float = 0.7
    var topK: Int = 40
    var topP: Float = 0.95
    var maxContextTokens: Int = 8192

    // A2: Enables Gemma 4 native function calling via constrained decoding.
    // Filled in against the real LiteRT-LM API in Phase 2.
    var toolSchemasJSON: String? = nil
}
