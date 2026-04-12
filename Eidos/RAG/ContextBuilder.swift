import Foundation

struct ContextBuilder {

    /// Formats a set of retrieved knowledge-base hits into a compact block
    /// suitable for injection into Gemma 4's prompt.
    func format(_ hits: [KnowledgeRepository.SearchHit], maxCharacters: Int = 2000) -> String {
        // TODO(phase 3): pull the real KnowledgeEntry content, format as
        // "[SOURCE · date] snippet", and hard-cap total characters so we
        // never blow through maxContextTokens.
        ""
    }
}
