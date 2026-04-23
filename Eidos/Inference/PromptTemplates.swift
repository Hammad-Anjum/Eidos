import Foundation

enum PromptTemplates {

    static let systemPrompt = """
    You are Eidos, a private on-device AI assistant. You have access to the user's \
    knowledge base, calendar, contacts, and reminders. Everything runs locally — \
    no data leaves the device. Be concise, personal, and useful. Never fabricate \
    facts about the user.
    """

    static let crystallizerSystemPrompt = """
    You are Eidos's memory-crystallizer. Your job is to read a conversation between \
    the user and the assistant, and extract durable facts worth remembering about \
    the USER (preferences, plans, relationships, decisions, deadlines). Ignore \
    assistant boilerplate, hedging, and speculative content.

    Return ONLY a JSON array (no prose, no markdown fences). Each item is an \
    object with these fields:
      - "title": short label (≤ 60 chars)
      - "body": the memorable content (markdown ok, multi-line ok)
      - "tags": array of lowercase keywords (optional)
      - "tier": one of "core_identity", "active_priorities", "topic" (optional; defaults to topic)
      - "priority": integer 1–5 where 1 is stickiest (optional; defaults to 3)

    If the conversation contains nothing worth remembering, return [].
    """

    /// Builds a message array for Gemma 4. MLX's tokenizer applies the
    /// model's chat template (`<start_of_turn>` tokens) automatically.
    static func chat(
        history: [(role: String, content: String)],
        userMessage: String,
        retrievedContext: String = "",
        toolSchemasJSON: String? = nil
    ) -> [[String: String]] {
        var system = systemPrompt
        if !retrievedContext.isEmpty {
            system += "\n\nRelevant context:\n" + retrievedContext
        }
        if let tools = toolSchemasJSON {
            system += "\n\nAvailable tools:\n" + tools
        }

        var messages: [[String: String]] = [["role": "system", "content": system]]
        for msg in history {
            messages.append(["role": msg.role == "user" ? "user" : "model", "content": msg.content])
        }
        messages.append(["role": "user", "content": userMessage])
        return messages
    }

    /// Builds a message array that asks Gemma to extract memorable facts
    /// from the given conversation. Output is consumed by
    /// `MemoryCrystallizer.parse` — must be JSON array only.
    static func crystallization(
        conversation: [(role: String, content: String)]
    ) -> [[String: String]] {
        let transcript = conversation
            .map { "\($0.role.uppercased()): \($0.content)" }
            .joined(separator: "\n\n")

        return [
            ["role": "system", "content": crystallizerSystemPrompt],
            ["role": "user", "content": """
            Extract memorable facts from this conversation. Return only the JSON array.

            <transcript>
            \(transcript)
            </transcript>
            """],
        ]
    }
}
