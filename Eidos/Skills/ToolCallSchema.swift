import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structured-generation schema for Gemma's tool calls.
///
/// When available (iOS 26+), `@Generable` compiles this into a grammar
/// that forces the model's token sampler to emit only tokens that
/// advance toward a valid instance of the type — i.e. 100% valid JSON
/// matching our schema, always.
///
/// On older iOS, this type is gated out and we fall back to the
/// retry-based path in `SkillParser` + `RAGPipeline.runWithToolLoop()`.
///
/// ## Why a separate type from `ToolCall`?
///
/// `ToolCall` is `Decodable` with `parameters: [String: AnyCodable]`
/// (heterogeneous bag) because iOS < 26 needs arbitrary JSON.
/// `@Generable` doesn't accept `[String: AnyCodable]` — it needs
/// typed fields. So we project to a flat schema with the most common
/// skill parameters and decode the rest post-generation.
#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ToolCallSchema: Equatable, Sendable {

    @Guide(description: "Name of the tool to call — must match a registered skill")
    let tool: String

    // Common parameters across Eidos skills. Most calls use one or two.
    // Unused fields get empty strings — cheap, and the skill's `invoke`
    // ignores blanks.

    @Guide(description: "Primary content — e.g. reminder title, note body, message body, search keyword")
    let title: String

    @Guide(description: "Optional ISO 8601 date-time — for reminders or events. Empty if not applicable.")
    let dueDate: String

    @Guide(description: "Optional secondary content — e.g. reminder notes, SMS body. Empty if not applicable.")
    let details: String

    @Guide(description: "Optional recipient — phone number, email, contact name. Empty if not applicable.")
    let recipient: String
}

/// Bridge from the structured Foundation Models schema back to the
/// heterogeneous `ToolCall` the rest of Eidos already consumes.
@available(iOS 26.0, macOS 26.0, *)
extension ToolCallSchema {
    func asToolCall() -> ToolCall {
        var params: [String: AnyCodable] = [:]
        if !title.isEmpty    { params["title"]     = AnyCodable(title) }
        if !dueDate.isEmpty  { params["due_date"]  = AnyCodable(dueDate) }
        if !details.isEmpty  { params["notes"]     = AnyCodable(details) }
        if !details.isEmpty  { params["body"]      = AnyCodable(details) }  // alias
        if !recipient.isEmpty {
            params["phone"] = AnyCodable(recipient)
            params["to"]    = AnyCodable(recipient)  // alias for email/SMS
            params["name"]  = AnyCodable(recipient)  // alias for contact
        }
        return ToolCall(tool: tool, parameters: params)
    }
}
#endif
