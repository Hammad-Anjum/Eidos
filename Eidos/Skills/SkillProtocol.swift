import Foundation

struct SkillResult: Sendable {
    let content: String
    let isError: Bool

    static func success(_ s: String) -> SkillResult { .init(content: s, isError: false) }
    static func failure(_ s: String) -> SkillResult { .init(content: s, isError: true) }
}

/// Why a permission-gated skill is unavailable. Surfaced in the
/// tool catalogue so Gemma knows NOT to call this tool, and (later)
/// in Diagnostics so the user can see why.
enum SkillAvailability: Sendable, Equatable {
    case available
    case permissionDenied(message: String)   // user explicitly denied
    case permissionNotDetermined              // never asked
    case featureFlagDisabled
    case unsupported(reason: String)         // device/iOS-level

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

protocol Skill: Sendable {
    var name: String { get }
    var description: String { get }
    var parametersSchema: String { get }
    func invoke(parameters: [String: AnyCodable]) async -> SkillResult

    /// Reports whether the skill can actually run right now. The
    /// `RAGPipeline` consults this BEFORE adding the skill to the
    /// tool catalogue Gemma sees. If unavailable, Gemma is never
    /// given the option to call it — preventing user-visible
    /// "permission denied" errors.
    ///
    /// Default implementation returns `.available` so existing
    /// pure-Swift skills (no platform permission) work unchanged.
    func availability() async -> SkillAvailability
}

extension Skill {
    func availability() async -> SkillAvailability { .available }
}
