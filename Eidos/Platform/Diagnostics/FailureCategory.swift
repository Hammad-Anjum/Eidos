import Foundation

/// Typed taxonomy of every failure mode Eidos can surface to its logger
/// or its telemetry pipeline.
///
/// Used as the `category` field on every logged error event, so we can
/// query "how many thermal trips in the last 24 h" or "which failure
/// modes dominate the first week of a user's install" without parsing
/// free-text error strings.
///
/// When a new throw site appears, the reviewer's checklist is:
///   1. Map it to an existing `FailureCategory`, or
///   2. Add a new case here with a clear comment on what qualifies.
///
/// Do NOT stuff multiple semantically distinct failures into
/// `.unknown` — that defeats the taxonomy.
enum FailureCategory: String, Sendable, Codable, CaseIterable {

    // MARK: - Model / inference

    /// `GemmaSession.load()` — MLX failed to memory-map or initialise
    /// the model. Could be missing files, incompatible weights, or OOM.
    case modelLoad

    /// `GemmaSession.generate()` — a generation call errored mid-stream
    /// or before the first token.
    case modelGenerate

    /// Generation aborted by the thermal guard; the phone was too hot
    /// to keep running the transformer.
    case modelThermal

    /// Process ran out of memory during MLX operations.
    case modelOOM

    /// Vision pipeline failed: image preprocessing, visual-token
    /// encoding, or VLM container rejecting the input.
    case modelVisionFailed

    /// Audio pipeline failed: resample, encode, or VLM rejecting the
    /// audio buffer.
    case modelAudioFailed

    /// Model load succeeded but the container reported a config mismatch
    /// we can't reconcile (e.g. VLM weights loaded into LLM-only path).
    case modelConfigMismatch

    // MARK: - RAG / knowledge

    /// `EmbeddingService.embed()` — NLContextualEmbedding failed to
    /// encode a chunk.
    case ragEmbed

    /// `KnowledgeRepository.search()` — retrieval failed at the
    /// vector-store or hybrid-search layer.
    case ragRetrieve

    // MARK: - Memory system

    /// Writing a memory entry to disk or to SwiftData failed.
    case memoryWrite

    /// Reading a memory entry failed — file gone, corrupted, or the
    /// SwiftData store is locked.
    case memoryRead

    /// `MemoryCrystallizer` ran but produced invalid output (bad JSON,
    /// empty result, etc.).
    case memoryCrystallize

    // MARK: - Download / onboarding

    /// Network-layer download failure: timeout, refused, DNS, TLS.
    case downloadNetwork

    /// Content-length or checksum mismatch after download.
    case downloadChecksum

    /// Pre-flight disk-space check failed OR the write itself failed
    /// because the destination filesystem ran out.
    case downloadDiskFull

    // MARK: - Permissions / capture

    /// User denied a permission the feature needs (mic, camera, photos,
    /// HealthKit, etc.).
    case permissionDenied

    /// `AVAudioSession.setCategory` / `setActive` threw, or the engine
    /// refused to start.
    case audioSessionFailed

    /// Camera hardware unavailable, PHPicker cancelled, or image decode
    /// failed.
    case cameraAccessFailed

    // MARK: - Actions / skills

    /// A skill's `execute()` method threw or returned an invalid payload.
    case skillExecute

    /// An App Intent invocation failed before it could hand off.
    case intentExecute

    /// A URL-scheme action was requested but `canOpenURL` returned false
    /// (target app not installed, unsupported scheme).
    case actionSchemeUnavailable

    // MARK: - Safety

    /// The `SafetyGate` intercepted a query (not strictly a "failure" —
    /// a successful refusal). Logged so we can audit frequency.
    case safetyGateTriggered

    // MARK: - Diagnostics meta

    /// The logger itself failed to persist to disk. Logged to the
    /// unified log only — never back through `EidosLogger` (would recurse).
    case loggerWriteFailed

    /// Benchmark runner caught an error while executing a benchmark
    /// prompt. The benchmark result is still recorded, marked failed.
    case benchmarkFailed

    /// Uncaught NSException or fatal POSIX signal intercepted by the
    /// crash-breadcrumb hooks in `EidosApp`. The app is about to die;
    /// this category exists so the final log line can be filtered to
    /// in Diagnostics → Logs.
    case crashHandler

    // MARK: - Fallback

    /// Genuinely unknown / unclassified. New cases should be promoted
    /// out of `.unknown` at first opportunity.
    case unknown

    /// Brief human-readable label suitable for the diagnostics UI.
    var displayLabel: String {
        switch self {
        case .modelLoad: "Model load"
        case .modelGenerate: "Generation"
        case .modelThermal: "Thermal throttle"
        case .modelOOM: "Out of memory"
        case .modelVisionFailed: "Vision pipeline"
        case .modelAudioFailed: "Audio pipeline"
        case .modelConfigMismatch: "Model config"
        case .ragEmbed: "Embed"
        case .ragRetrieve: "Retrieval"
        case .memoryWrite: "Memory write"
        case .memoryRead: "Memory read"
        case .memoryCrystallize: "Crystallize"
        case .downloadNetwork: "Network"
        case .downloadChecksum: "Checksum"
        case .downloadDiskFull: "Disk full"
        case .permissionDenied: "Permission denied"
        case .audioSessionFailed: "Audio session"
        case .cameraAccessFailed: "Camera"
        case .skillExecute: "Skill"
        case .intentExecute: "Intent"
        case .actionSchemeUnavailable: "Scheme unavailable"
        case .safetyGateTriggered: "Safety gate"
        case .loggerWriteFailed: "Logger write"
        case .benchmarkFailed: "Benchmark"
        case .crashHandler: "Crash handler"
        case .unknown: "Unknown"
        }
    }
}
