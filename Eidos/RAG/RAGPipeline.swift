import Foundation

/// Single-pass RAG chat: builds a memory + KB context block, fires one
/// streaming call to Gemma with the augmented prompt. Tool calls (if any)
/// are embedded in the token stream and detected by `SkillParser` upstream.
///
/// Per `plan.md §A2`, Gemma 4's native function-calling lets us do this in
/// one pass — the model decides inline whether to answer or invoke a skill.
@MainActor
final class RAGPipeline {

    private let gemma: GemmaSession
    private let knowledgeRepo: KnowledgeRepository
    private let memoryManager: MemoryManager
    private let skillRegistry: SkillRegistry
    private let contextBuilder: ContextBuilder

    init(
        gemma: GemmaSession,
        knowledgeRepo: KnowledgeRepository,
        memoryManager: MemoryManager,
        skillRegistry: SkillRegistry
    ) {
        self.gemma = gemma
        self.knowledgeRepo = knowledgeRepo
        self.memoryManager = memoryManager
        self.skillRegistry = skillRegistry
        self.contextBuilder = ContextBuilder(
            memoryManager: memoryManager,
            knowledgeRepo: knowledgeRepo
        )
    }

    /// Streams tokens from Gemma for `userMessage`, augmented with
    /// retrieved memory + KB context.
    ///
    /// Prior-turn `history` is passed through to keep multi-turn coherence.
    /// The caller is expected to append the assistant's final text to its
    /// own message log; the pipeline itself doesn't persist the conversation.
    func chat(
        userMessage: String,
        history: [(role: String, content: String)]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let context = await contextBuilder.build(query: userMessage)
        let messages = PromptTemplates.chat(
            history: history,
            userMessage: userMessage,
            retrievedContext: context.text
        )
        return try await gemma.generate(messages: messages)
    }
}
