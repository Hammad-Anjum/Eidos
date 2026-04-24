package com.hissamuddin.eidos.platform.diagnostics

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Crash-safe structured logger that persists JSONL to the app's sandbox and
 * mirrors to Android's unified logcat.
 *
 * ## Schema
 *
 * Each log line is a single JSON object on its own line:
 * ```
 * {"ts":"2026-04-25T14:30:00.123Z","level":"info","category":"model","msg":"Model loaded","data":{"variant":"e2b"}}
 * ```
 *
 * Fields:
 *  - `ts`: ISO-8601 UTC, millisecond precision.
 *  - `level`: one of [LogLevel].
 *  - `category`: free-form string; use one of the constants in [LogCategory].
 *  - `msg`: short human-readable message.
 *  - `data`: optional [JsonElement] — any structured payload you'd want to
 *    filter on later. Keep it small; bulk data belongs in [MetricsRecorder].
 *
 * ## Contract
 *
 *  - Writes happen on [Dispatchers.IO]. Never blocks the caller's dispatcher.
 *  - **Logger failure never crashes the app.** All I/O is guarded; failures
 *    drop the line and increment [droppedWrites].
 *  - Files live at `filesDir/eidos/logs/YYYY-MM-DD.jsonl`. Never rotated —
 *    the iOS side chose this discipline deliberately (complete history for
 *    benchmark + post-mortem). A future cleanup pass can compress or prune
 *    once size becomes a problem.
 *
 * ## UI hook
 *
 * Diagnostics collects [logStream] to display a live tail. Backpressure is
 * handled by [BufferOverflow.DROP_OLDEST] — the UI cannot back-pressure the
 * logger into dropping useful production writes.
 */
class EidosLogger internal constructor(
    private val logsDir: File,
    private val scope: CoroutineScope,
    private val nowUtcIso: () -> String = { defaultIsoNow() },
) {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    private val _logStream = MutableSharedFlow<LogRecord>(
        replay = TAIL_REPLAY,
        extraBufferCapacity = STREAM_BUFFER,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /** Live stream of log events. Diagnostics UI collects this for the tail view. */
    val logStream: SharedFlow<LogRecord> = _logStream.asSharedFlow()

    /** Monotonically increasing count of writes that failed for any reason. */
    @Volatile
    var droppedWrites: Long = 0L
        private set

    fun debug(category: String, msg: String, data: JsonElement? = null) =
        log(LogLevel.DEBUG, category, msg, data)

    fun info(category: String, msg: String, data: JsonElement? = null) =
        log(LogLevel.INFO, category, msg, data)

    fun warn(category: String, msg: String, data: JsonElement? = null) =
        log(LogLevel.WARN, category, msg, data)

    fun error(
        category: String,
        msg: String,
        data: JsonElement? = null,
        failure: FailureCategory = FailureCategory.UNKNOWN,
    ) = log(LogLevel.ERROR, category, msg, data, failure)

    /** Use for metrics-grade events. Persisted but shown in Metrics tab rather than Logs tab. */
    fun metric(category: String, msg: String, data: JsonElement? = null) =
        log(LogLevel.METRIC, category, msg, data)

    private fun log(
        level: LogLevel,
        category: String,
        msg: String,
        data: JsonElement?,
        failure: FailureCategory? = null,
    ) {
        val record = LogRecord(
            ts = nowUtcIso(),
            level = level.wire,
            category = category,
            msg = msg,
            data = data,
            failure = failure?.name,
        )

        // 1) Mirror to logcat synchronously so `adb logcat` captures everything.
        //    Cheap and non-blocking.
        mirrorToLogcat(level, category, msg)

        // 2) Fan out to live UI tail (drop-oldest if saturated — documented).
        _logStream.tryEmit(record)

        // 3) Persist off the hot path. Dispatcher is controlled by the scope
        //    the logger was constructed with — production uses Dispatchers.IO
        //    (see the `create()` factory); tests substitute a TestScope.
        scope.launch {
            persist(record)
        }
    }

    private fun mirrorToLogcat(level: LogLevel, category: String, msg: String) {
        val tag = "Eidos/$category"
        when (level) {
            LogLevel.DEBUG -> Log.d(tag, msg)
            LogLevel.INFO -> Log.i(tag, msg)
            LogLevel.WARN -> Log.w(tag, msg)
            LogLevel.ERROR -> Log.e(tag, msg)
            LogLevel.METRIC -> Log.v(tag, msg)
        }
    }

    private fun persist(record: LogRecord) {
        try {
            val file = fileFor(record.ts)
            file.parentFile?.mkdirs()
            file.appendText(json.encodeToString(LogRecord.serializer(), record) + "\n")
        } catch (t: Throwable) {
            // Logger failure never crashes the app (engineering bar rule #6).
            droppedWrites++
            Log.e(TAG, "persist failed: ${t.javaClass.simpleName}: ${t.message}")
        }
    }

    private fun fileFor(isoTimestamp: String): File {
        val day = isoTimestamp.substring(0, 10) // YYYY-MM-DD
        return File(logsDir, "$day.jsonl")
    }

    /**
     * Returns the current day's log file. Useful for the "Export logs" flow
     * in Diagnostics (A9 submission polish). Returns null if the file does
     * not exist yet.
     */
    fun currentLogFile(): File? {
        val file = fileFor(nowUtcIso())
        return if (file.exists()) file else null
    }

    /**
     * Returns every log file present on disk, newest first. Used for the
     * "Export all" share flow.
     */
    fun allLogFiles(): List<File> =
        logsDir.listFiles { f -> f.isFile && f.extension == "jsonl" }
            ?.sortedByDescending { it.name }
            ?: emptyList()

    companion object {
        private const val TAG = "EidosLogger"
        private const val TAIL_REPLAY = 200
        private const val STREAM_BUFFER = 256

        private val ISO_FORMATTER = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        private fun defaultIsoNow(): String =
            synchronized(ISO_FORMATTER) { ISO_FORMATTER.format(Date()) }

        /**
         * Standard constructor. Creates the logger rooted at
         * `context.filesDir/eidos/logs/` and backed by a supervisor scope so
         * a single failed write never cancels the pipeline.
         */
        fun create(context: Context): EidosLogger {
            val dir = File(context.filesDir, "eidos/logs")
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            return EidosLogger(dir, scope)
        }
    }
}

/** Level of a single log event. `metric` is reserved for structured numbers. */
enum class LogLevel(val wire: String) {
    DEBUG("debug"),
    INFO("info"),
    WARN("warn"),
    ERROR("error"),
    METRIC("metric"),
}

/** Canonical categories. Free-form strings are permitted, but prefer these. */
object LogCategory {
    const val MODEL = "model"
    const val CHAT = "chat"
    const val MEMORY = "memory"
    const val RAG = "rag"
    const val DOWNLOAD = "download"
    const val PERMISSION = "permission"
    const val UI = "ui"
    const val INTENT = "intent"
    const val SKILL = "skill"
    const val PERSONA = "persona"
    const val CRASH = "crash"
    const val BENCHMARK = "benchmark"
    const val LIFECYCLE = "lifecycle"
}

/**
 * Serializable log record. Public so release-mode R8 keeps it (see
 * `proguard-rules.pro`).
 */
@Serializable
data class LogRecord(
    val ts: String,
    val level: String,
    val category: String,
    val msg: String,
    val data: JsonElement? = null,
    val failure: String? = null,
)
