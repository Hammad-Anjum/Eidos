import Foundation
import SwiftData

// Thin owner of the SwiftData container. Kept as a separate file per
// architecture.md §3. In practice the ModelContainer is constructed in
// AppContainer.init so this file is currently a home for any store-level
// utilities we add later (migration helpers, vacuum, export).
enum KnowledgeStore {
    static let schema = Schema([
        KnowledgeEntry.self,
        EmbeddingRecord.self,
        Conversation.self,
        ConversationMessage.self,
    ])
}
