package com.hissamuddin.eidos.knowledgebase

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Root Room database. A0 declares the schema; DAOs and the sqlite-vec
 * extension loader arrive in A1.
 *
 * The DB lives under `filesDir/eidos/eidos.db`. Combined with the
 * `EncryptedFile`-backed memory tier files, this is the full on-device
 * personal data footprint — no external cache, no backup replication (see
 * `backup_rules.xml` + `data_extraction_rules.xml`).
 */
@Database(
    entities = [
        KnowledgeEntry::class,
        EmbeddingRecord::class,
        Conversation::class,
        ConversationMessage::class,
        MemoryEntry::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class KnowledgeDatabase : RoomDatabase() {
    // DAOs land in A1:
    //   abstract fun knowledgeDao(): KnowledgeDao
    //   abstract fun embeddingDao(): EmbeddingDao
    //   abstract fun conversationDao(): ConversationDao
    //   abstract fun memoryDao(): MemoryDao

    companion object {
        private const val DB_NAME = "eidos.db"

        @Volatile
        private var instance: KnowledgeDatabase? = null

        /**
         * Process-wide singleton. Room's own internal locking handles
         * concurrent access; we just guard the one-time builder.
         */
        fun get(context: Context): KnowledgeDatabase =
            instance ?: synchronized(this) {
                instance ?: build(context).also { instance = it }
            }

        private fun build(context: Context): KnowledgeDatabase =
            Room.databaseBuilder(
                context.applicationContext,
                KnowledgeDatabase::class.java,
                DB_NAME,
            )
                // A1 will add a RoomDatabase.Callback that loads sqlite-vec
                // in onOpen().
                .fallbackToDestructiveMigrationOnDowngrade()
                .build()
    }
}
