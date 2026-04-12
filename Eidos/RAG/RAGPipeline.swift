import Foundation

// Single-pass RAG + tools pipeline. Per plan.md §A2, Gemma 4's native
// function calling replaces the spec's two-pass skill-detection flow: the
// model decides in one streaming pass whether to call a tool or answer.
// Tool calls are detected on the token stream by SkillParser.
@MainActor
final class RAGPipeline {

    private let gemma: GemmaSession
    private let knowledgeRepo: KnowledgeRepository
    private let skillRegistry: SkillRegistry
    private let contextBuilder = ContextBuilder()

    init(
        gemma: GemmaSession,
        knowledgeRepo: KnowledgeRepository,
        skillRegistry: SkillRegistry
    ) {
        self.gemma = gemma
        self.knowledgeRepo = knowledgeRepo
        self.skillRegistry = skillRegistry
    }

    func chat(
        userMessage: String,
        history: [ConversationMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: GemmaError.notLoaded)
        }
    }
}
