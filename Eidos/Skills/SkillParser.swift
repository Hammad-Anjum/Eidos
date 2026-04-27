import Foundation

struct ToolCall: Decodable, Sendable {
    let tool: String
    let parameters: [String: AnyCodable]

    init(tool: String, parameters: [String: AnyCodable]) {
        self.tool = tool
        self.parameters = parameters
    }

    // Decodable init matches the JSON shape Gemma emits.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tool = try c.decode(String.self, forKey: .tool)
        self.parameters = try c.decodeIfPresent([String: AnyCodable].self, forKey: .parameters) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case tool, parameters }
}

/// Parses Gemma 4's native function-call JSON from the token stream.
///
/// Two layers of robustness:
/// 1. **Strict parse**: assume the whole output IS a single JSON object
///    (the ideal path — prompt asks for JSON only).
/// 2. **Prose-wrapped recovery**: if strict fails, scan for a balanced
///    `{…}` block anywhere in the output. Handles cases where the
///    model prefixes/suffixes the JSON with stray prose despite being
///    told not to.
struct SkillParser {

    /// Attempts strict parse first, then falls back to extracting a
    /// balanced JSON object from prose. Returns nil only if neither
    /// path yields a decodable `ToolCall`.
    func parse(_ output: String) -> ToolCall? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strict path — whole output is the JSON.
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let call = try? JSONDecoder().decode(ToolCall.self, from: data) {
            return call
        }

        // Recovery path — find the first balanced {…} and try that.
        if let snippet = Self.firstBalancedObject(in: trimmed),
           let data = snippet.data(using: .utf8),
           let call = try? JSONDecoder().decode(ToolCall.self, from: data) {
            return call
        }

        return nil
    }

    /// Returns the substring of the first balanced `{…}` object in `s`.
    /// Respects string literals so `{` / `}` inside strings don't throw
    /// off the depth counter. Returns nil if none found.
    static func firstBalancedObject(in s: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escape = false
        for i in s.indices {
            let c = s[i]
            if escape { escape = false; continue }
            if inString {
                if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "{":
                if depth == 0 { start = i }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let s0 = start {
                    return String(s[s0...i])
                }
            default: break
            }
        }
        return nil
    }
}
