package com.hissamuddin.eidos.knowledgebase

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One chat thread. New threads are created with the `+` button in ChatScreen;
 * the most-recent thread auto-resumes on launch (see ChatViewModel in A2/A3).
 */
@Entity(
    tableName = "conversation",
    indices = [Index(value = ["updatedAtMs"])],
)
data class Conversation(
    @PrimaryKey val id: String,
    val title: String?,           // null until crystallizer names it
    val createdAtMs: Long,
    val updatedAtMs: Long,
)
