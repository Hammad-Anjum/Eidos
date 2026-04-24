package com.hissamuddin.eidos.knowledgebase

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * A unit of knowledge ingested into Eidos: a URL, a shared article, a WhatsApp
 * thread, a manual note. The text is chunked (see `TextChunker` in A1) and
 * each chunk gets an [EmbeddingRecord].
 *
 * `contentHash` enables idempotent re-ingestion — re-importing the same
 * WhatsApp export or re-sharing the same URL is a no-op.
 */
@Entity(
    tableName = "knowledge_entry",
    indices = [
        Index(value = ["contentHash"], unique = true),
        Index(value = ["source"]),
        Index(value = ["createdAtMs"]),
    ],
)
data class KnowledgeEntry(
    @PrimaryKey val id: String,
    val source: String,            // "share_url", "whatsapp_import", "mail_import", "manual", ...
    val title: String,
    val content: String,
    val contentHash: String,       // SHA-256 of content; uniqueness enforced above
    val tags: String,              // comma-delimited; Room doesn't handle List<String> natively
    val createdAtMs: Long,
    val updatedAtMs: Long,
)
