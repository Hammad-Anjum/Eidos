package com.hissamuddin.eidos.platform.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Schema-stability guards. These tests don't exercise logic — they lock in
 * the wire names of [FailureCategory] so accidentally reordering or renaming
 * an entry breaks CI loudly (the category name ends up in persistent JSONL).
 */
class FailureCategoryTest {

    @Test
    fun `enum names are stable wire strings`() {
        // Spot-check: if someone reorders the enum, these assertions still
        // pass (enum name is string-backed). If someone renames, these fail.
        assertEquals("MODEL_LOAD", FailureCategory.MODEL_LOAD.name)
        assertEquals("MODEL_GENERATE", FailureCategory.MODEL_GENERATE.name)
        assertEquals("RAG_EMBED", FailureCategory.RAG_EMBED.name)
        assertEquals("MEMORY_WRITE", FailureCategory.MEMORY_WRITE.name)
        assertEquals("DOWNLOAD_NETWORK", FailureCategory.DOWNLOAD_NETWORK.name)
        assertEquals("PERMISSION_DENIED", FailureCategory.PERMISSION_DENIED.name)
        assertEquals("SKILL_EXECUTE", FailureCategory.SKILL_EXECUTE.name)
        assertEquals("UNKNOWN", FailureCategory.UNKNOWN.name)
    }

    @Test
    fun `UNKNOWN is present as the catch-all`() {
        // Callers use UNKNOWN as the default when they don't have a better
        // category. If it disappears, every error site breaks.
        assertTrue(FailureCategory.entries.any { it == FailureCategory.UNKNOWN })
    }

    @Test
    fun `every category round-trips through valueOf`() {
        FailureCategory.entries.forEach { category ->
            assertEquals(category, FailureCategory.valueOf(category.name))
        }
    }
}
