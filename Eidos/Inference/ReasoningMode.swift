import Foundation

/// How heavily Gemma should reason before producing an answer.
///
/// `.fast` is the default for user-facing chat — low latency, single pass.
/// `.reasoning` inserts a chain-of-thought prefix that encourages the
/// model to enumerate steps before producing an answer. Higher quality
/// on complex queries (digest, persona dispatch, skill conflict
/// resolution) at the cost of tokens and wall time.
///
/// Gemma 4 has a native "thinking" mode — we invoke it via a system-
/// prompt prefix rather than a sampling parameter, so this is portable
/// across MLX binding changes.
enum ReasoningMode: String, Sendable, CaseIterable, Codable {
    case fast
    case reasoning

    /// System-prompt prefix to inject ahead of the caller's system
    /// prompt. Empty for `.fast`.
    var systemPrefix: String {
        switch self {
        case .fast:
            ""
        case .reasoning:
            """
            Think step-by-step before you answer. First, briefly enumerate the \
            sub-questions or facts you need. Then, produce the final answer. \
            If you need to make assumptions, state them.

            """
        }
    }

    /// Whether callers should expect a noticeably longer response time
    /// and token count. The UI uses this to show a "thinking…" state.
    var isHeavyweight: Bool {
        self == .reasoning
    }
}
