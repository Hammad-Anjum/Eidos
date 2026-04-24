package com.hissamuddin.eidos.platform.diagnostics

import app.cash.turbine.test
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Unit tests for [EidosLogger]. Covers:
 *  - JSONL schema fields exist and parse cleanly
 *  - Log file lands at `logsDir/YYYY-MM-DD.jsonl`
 *  - Live log stream emits records in order
 *  - Logger failure never throws (simulated via an invalid output path)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EidosLoggerTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val fixedIso = "2026-04-25T12:34:56.789Z"
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `info() persists one JSONL line with the expected schema`() = runTest {
        val dir = tmp.newFolder("logs")
        val logger = newLogger(dir, this)

        logger.info(LogCategory.MODEL, "hello", buildJsonObject {
            put("variant", "e2b")
        })
        advanceUntilIdle()

        val file = File(dir, "2026-04-25.jsonl")
        assertTrue("log file should exist", file.exists())
        val lines = file.readLines()
        assertEquals(1, lines.size)

        val record = json.decodeFromString(LogRecord.serializer(), lines.single())
        assertEquals(fixedIso, record.ts)
        assertEquals("info", record.level)
        assertEquals(LogCategory.MODEL, record.category)
        assertEquals("hello", record.msg)
        assertNotNull(record.data)
        assertNull(record.failure)
    }

    @Test
    fun `error() records a failure category in the wire JSON`() = runTest {
        val dir = tmp.newFolder("logs")
        val logger = newLogger(dir, this)

        logger.error(
            category = LogCategory.MODEL,
            msg = "boom",
            failure = FailureCategory.MODEL_THERMAL,
        )
        advanceUntilIdle()

        val record = json.decodeFromString(
            LogRecord.serializer(),
            File(dir, "2026-04-25.jsonl").readText().trim(),
        )
        assertEquals("error", record.level)
        assertEquals("MODEL_THERMAL", record.failure)
    }

    @Test
    fun `logStream emits records the UI can subscribe to`() = runTest {
        val dir = tmp.newFolder("logs")
        val logger = newLogger(dir, this)

        logger.logStream.test {
            logger.info(LogCategory.UI, "composed")
            val emitted = awaitItem()
            assertEquals("composed", emitted.msg)
            assertEquals("info", emitted.level)
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `persistence failure does not throw from the call site`() = runTest {
        // Point the logger at a path where the parent is a FILE rather than
        // a directory — `file.parentFile?.mkdirs()` fails and `appendText`
        // throws. The logger's try/catch must eat it and increment
        // droppedWrites. The `runTest` scope would fail the test if an
        // uncaught exception escaped.
        val notADir = tmp.newFile("not_a_directory")
        val logger = newLogger(notADir, this)

        logger.warn(LogCategory.CRASH, "this should never crash the app")
        advanceUntilIdle()

        assertTrue("dropped writes should increment on failure", logger.droppedWrites >= 1L)
    }

    private fun newLogger(dir: File, scope: CoroutineScope): EidosLogger =
        EidosLogger(
            logsDir = dir,
            scope = scope,
            nowUtcIso = { fixedIso },
        )
}
