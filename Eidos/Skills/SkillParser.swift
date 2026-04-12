import Foundation

struct ToolCall: Decodable, Sendable {
    let tool: String
    let parameters: [String: AnyCodable]
}

// Per plan.md §A2, this parser reads Gemma 4's native function-call
// output format. The exact token-level shape of a function call is
// determined by the LiteRT-LM constrained-decoding API and fixed in
// Phase 2 — this stub exists so the rest of the pipeline compiles.
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
