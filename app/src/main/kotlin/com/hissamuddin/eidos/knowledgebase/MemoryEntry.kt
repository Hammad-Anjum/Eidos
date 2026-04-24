package com.hissamuddin.eidos.knowledgebase

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Personal memory entry — what Eidos has learned about the user. Tiered
 * P0 (core identity) → P5 (archive) with priority-based decay and
 * end-of-session crystallization (A3).
 */
@Entity(
    tableName = "memory_entry",
    indices = [
        Index(value = ["tier"]),
        Index(value = ["priority"]),
        Index(value = ["lastTouchedAtMs"]),
    ],
)
data class MemoryEntry(
    @PrimaryKey val id: String,
    val tier: String,              // "core_identity" | "active" | "topic" | "recent" | "archive"
    val priority: Int,             // 0 (core) .. 5 (archive)
    val title: String,
    val body: String,
    val frontmatter: String,       // raw YAML frontmatter for round-tripping on export
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val lastTouchedAtMs: Long,     // resets on access; drives decay
)
