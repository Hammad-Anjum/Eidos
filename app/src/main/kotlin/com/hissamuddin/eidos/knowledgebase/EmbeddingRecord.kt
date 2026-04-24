package com.hissamuddin.eidos.knowledgebase

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One embedded chunk. Vector lives as a raw `ByteArray` — sqlite-vec consumes
 * byte blobs directly, and we avoid per-row boxing of Float[] in Kotlin.
 *
 * `dim` is stored per-row so mixed-dimension embeddings (if we ever mix
 * MediaPipe TextEmbedder + ONNX MiniLM during A1 validation) remain
 * queryable.
 */
@Entity(
    tableName = "embedding_record",
    foreignKeys = [
        ForeignKey(
            entity = KnowledgeEntry::class,
            parentColumns = ["id"],
            childColumns = ["entryId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(value = ["entryId"]),
        Index(value = ["chunkIndex"]),
    ],
)
data class EmbeddingRecord(
    @PrimaryKey val id: String,
    val entryId: String,
    val chunkIndex: Int,
    val chunkText: String,
    val vector: ByteArray,         // Float32 little-endian, length = dim * 4
    val dim: Int,
    val createdAtMs: Long,
) {
    // ByteArray's default equals/hashCode is reference-based, which breaks
    // Room's generated diffing. Override to content-based comparison.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EmbeddingRecord) return false
        return id == other.id &&
            entryId == other.entryId &&
            chunkIndex == other.chunkIndex &&
            chunkText == other.chunkText &&
            vector.contentEquals(other.vector) &&
            dim == other.dim &&
            createdAtMs == other.createdAtMs
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + entryId.hashCode()
        result = 31 * result + chunkIndex
        result = 31 * result + chunkText.hashCode()
        result = 31 * result + vector.contentHashCode()
        result = 31 * result + dim
        result = 31 * result + createdAtMs.hashCode()
        return result
    }
}
