import Foundation
import SwiftData

@Model
final class EmbeddingRecord {
    var id: UUID
    var chunkIndex: Int
    var chunkText: String   // The actual chunk text (shown in retrieval UI)
    var vector: Data        // [Float] serialised as raw bytes

    init(chunkIndex: Int, chunkText: String, vector: [Float]) {
        self.id = UUID()
        self.chunkIndex = chunkIndex
        self.chunkText = chunkText
        self.vector = Data(bytes: vector, count: vector.count * MemoryLayout<Float>.stride)
    }

    var floatVector: [Float] {
        vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade)
    var messages: [ConversationMessage] = []

    init(title: String = "New conversation") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ConversationMessage {
    var id: UUID
    var role: String        // "user" | "assistant" | "system" | "tool_result"
    var content: String
    var timestamp: Date
    var skillCallJSON: String?

    init(role: String, content: String, skillCallJSON: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.skillCallJSON = skillCallJSON
    }
}

