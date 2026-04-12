import Foundation

// Gemma 4 instruction-tuned chat format.
// Reference: https://ai.google.dev/gemma/docs/formatting
//
// Per plan.md §A2, Phase 3 replaces the two-pass skill-detection flow
// with Gemma 4's native function calling — a single template that takes
// tool schemas + retrieved context + history, and the model chooses
// whether to emit a function call or a natural-language response in one
// streaming pass.
//
// This file is a Phase 0 placeholder. The real templates land in Phase 2
// (basic chat) and Phase 3 (chat + tools).
enum PromptTemplates {

    static let systemPrompt = """
    You are Eidos, a private local AI assistant. You have access to the user's personal \
    knowledge base — notes, calendar events, contacts, and imported data from apps. \
    Everything runs on-device. Be concise, personal, and genuinely useful. \
    When you don't know something, say so clearly. Never fabricate facts about the user.
    """

    static func chat(
        history: [ConversationMessage],
        userMessage: String,
        retrievedContext: String,
        toolSchemasJSON: String? = nil
    ) -> String {
        // TODO(phase 2): real Gemma 4 prompt formatting.
        ""
    }
}
