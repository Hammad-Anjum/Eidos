import Foundation

struct ToolCall: Decodable, Sendable {
    let tool: String
    let parameters: [String: AnyCodable]
}

/// Parses Gemma 4's native function-call JSON from the token stream.
struct SkillParser {
    func parse(_ output: String) -> ToolCall? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
              let data = trimmed.data(using: .utf8),
              let call = try? JSONDecoder().decode(ToolCall.self, from: data)
        else { return nil }
        return call
    }
}
