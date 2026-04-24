package com.hissamuddin.eidos.knowledgebase

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Single turn in a [Conversation]. `role` uses the same wire names as
 * [com.hissamuddin.eidos.inference.ChatMessage.Role] — "system" | "user" |
 * "assistant" | "tool".
 *
 * Streaming writes are incremental: `content` is flushed to disk every N
 * tokens (or every 500 ms) so a crash mid-stream doesn't lose the response.
 */
@Entity(
    tableName = "conversation_message",
    foreignKeys = [
        ForeignKey(
            entity = Conversation::class,
            parentColumns = ["id"],
            childColumns = ["conversationId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(value = ["conversationId"]),
        Index(value = ["createdAtMs"]),
    ],
)
data class ConversationMessage(
    @PrimaryKey val id: String,
    val conversationId: String,
    val role: String,              // "system" | "user" | "assistant" | "tool"
    val content: String,
    val createdAtMs: Long,
    val updatedAtMs: Long,
)
