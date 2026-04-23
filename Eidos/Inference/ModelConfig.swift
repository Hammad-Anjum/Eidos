import Foundation

enum DeviceClass: Sendable {
    case standard  // 4-6 GB RAM (iPhone 13, 14, 15)
    case pro       // 8+ GB RAM (iPhone 15 Pro, 16, 16 Pro)

    static var current: DeviceClass {
        ProcessInfo.processInfo.physicalMemory >= 7_500_000_000 ? .pro : .standard
    }
}

enum GemmaVariant: String, CaseIterable, Sendable {
    // HuggingFace's `resolve/main/` endpoint is case-sensitive — these
    // must match the canonical lowercase paths of the mlx-community repos.
    case e2b = "mlx-community/gemma-4-e2b-it-4bit"
    case e4b = "mlx-community/gemma-4-e4b-it-4bit"

    var displayName: String {
        switch self {
        case .e2b: "Gemma 4 E2B (faster, ~3.4 GB)"
        case .e4b: "Gemma 4 E4B (smarter, ~5.3 GB)"
        }
    }

    var huggingFaceID: String { rawValue }

    /// Subdirectory inside `Documents/` where weights are stored locally.
    var localDirectoryName: String {
        switch self {
        case .e2b: "gemma-e2b"
        case .e4b: "gemma-e4b"
        }
    }

    /// Approximate total bytes across all files in the HF repo (weights
    /// + tokenizer + configs). Used for the disk-space preflight, so
    /// we intentionally round generously.
    var approximateDiskBytes: Int64 {
        switch self {
        case .e2b: 3_500_000_000   // ~3.3 GB weights + 31 MB tokenizer + configs
        case .e4b: 5_500_000_000   // ~5.25 GB weights + configs
        }
    }

    var requiredDeviceClass: DeviceClass {
        switch self {
        case .e2b: .standard
        case .e4b: .pro
        }
    }

    var isAvailableOnThisDevice: Bool {
        switch (requiredDeviceClass, DeviceClass.current) {
        case (.standard, _): true
        case (.pro, .pro): true
        case (.pro, .standard): false
        }
    }

    static var defaultForDevice: GemmaVariant {
        DeviceClass.current == .pro ? .e4b : .e2b
    }
}

struct ModelConfig: Sendable {
    var variant: GemmaVariant = .defaultForDevice
    var maxTokens: Int = 1024
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var toolSchemasJSON: String?
}
