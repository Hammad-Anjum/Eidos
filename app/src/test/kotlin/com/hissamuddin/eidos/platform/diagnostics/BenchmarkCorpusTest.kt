package com.hissamuddin.eidos.platform.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Corpus-integrity checks. These guard against silent breakage of the
 * benchmark harness when new prompts are added.
 */
class BenchmarkCorpusTest {

    @Test
    fun `prompt ids are unique`() {
        val ids = BenchmarkCorpus.prompts.map { it.id }
        assertEquals(
            "duplicate prompt ids: ${ids.groupingBy { it }.eachCount().filter { it.value > 1 }}",
            ids.size,
            ids.toSet().size,
        )
    }

    @Test
    fun `every prompt has non-empty text`() {
        BenchmarkCorpus.prompts.forEach { prompt ->
            assertTrue("empty text in ${prompt.id}", prompt.text.isNotBlank())
        }
    }

    @Test
    fun `at least one prompt exists per category that has shipped content`() {
        // Short-chat + reasoning + refusal + hallucination are content-bearing
        // as of A0. Other categories are placeholders until their owning phase
        // fills them in.
        val shippedCategories = setOf(
            BenchmarkCorpus.Category.SHORT_CHAT,
            BenchmarkCorpus.Category.REASONING,
            BenchmarkCorpus.Category.REFUSAL,
            BenchmarkCorpus.Category.HALLUCINATION,
        )
        shippedCategories.forEach { cat ->
            assertTrue(
                "no prompts for shipped category $cat",
                BenchmarkCorpus.byCategory(cat).isNotEmpty(),
            )
        }
    }

    @Test
    fun `keyword rubric is case-insensitive`() {
        val rubric = Rubric.Keyword(oneOf = listOf("helpline"))
        assertTrue(rubric.scores("Please call the Helpline at 988."))
        assertTrue(rubric.scores("HELPLINE information..."))
        assertFalse(rubric.scores("nothing of relevance here"))
    }
}
