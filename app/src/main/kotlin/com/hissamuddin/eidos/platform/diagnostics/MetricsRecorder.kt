package com.hissamuddin.eidos.platform.diagnostics

import android.os.Debug
import android.os.PowerManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Per-generation metrics collector. Records TTFT, tokens/sec, RSS, and
 * thermal state for every model call so we can (a) show the user the cost of
 * each turn in Diagnostics and (b) reduce future PRs to "show me the numbers"
 * instead of "feels faster".
 *
 * ## Schema
 *
 * Each record lives in JSONL (persisted via [EidosLogger] at [LogLevel.METRIC])
 * with shape:
 * ```
 * {
 *   "requestId": "a3f9-...",
 *   "tag": "chat",              // chat | digest | benchmark | crystallize | ...
 *   "ttftMs": 412,
 *   "tokensOut": 57,
 *   "tokensPerSec": 11.2,
 *   "rssBeforeKb": 180_345,
 *   "rssPeakKb": 210_540,
 *   "rssAfterKb": 184_012,
 *   "thermal": "nominal",       // nominal|light|moderate|severe|critical|emergency|shutdown
 *   "reasoning": false
 * }
 * ```
 *
 * ## Usage pattern
 *
 * ```kotlin
 * val probe = metrics.start(tag = "chat")
 * gemma.generate(prompt).collect { token ->
 *     probe.onToken()
 *     // ...
 * }
 * probe.finish(tokensOut = n)
 * ```
 */
class MetricsRecorder internal constructor(
    private val logger: EidosLogger,
    private val thermalStatusProvider: () -> Int,
    private val clockMs: () -> Long = System::currentTimeMillis,
) {
    private val json = Json { encodeDefaults = false }

    private val _recent = MutableStateFlow<List<MetricRecord>>(emptyList())

    /** Ring of recent metrics for the Diagnostics → Metrics table. */
    val recent: StateFlow<List<MetricRecord>> = _recent.asStateFlow()

    /**
     * Begin a measurement. The returned [Probe] MUST be finished (via
     * [Probe.finish] or [Probe.abort]); unfinished probes never publish a
     * record and the ring stays clean.
     */
    fun start(tag: String, reasoning: Boolean = false): Probe {
        val rssBefore = currentRssKb()
        return Probe(
            requestId = newRequestId(),
            tag = tag,
            reasoning = reasoning,
            startedAtMs = clockMs(),
            rssBeforeKb = rssBefore,
        )
    }

    private fun record(record: MetricRecord) {
        _recent.update { (listOf(record) + it).take(RECENT_CAP) }

        logger.metric(
            category = LogCategory.BENCHMARK,
            msg = "gen:${record.tag}",
            data = runCatching { json.encodeToJsonElement(MetricRecord.serializer(), record) }
                .getOrElse { JsonNull },
        )
    }

    private fun currentRssKb(): Long {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        return info.totalPss.toLong()
    }

    private fun currentThermal(): ThermalState =
        ThermalState.fromPlatform(thermalStatusProvider())

    /**
     * One in-flight measurement. Not thread-safe — callers must not share a
     * single Probe across concurrent generations.
     */
    inner class Probe internal constructor(
        val requestId: String,
        private val tag: String,
        private val reasoning: Boolean,
        private val startedAtMs: Long,
        private val rssBeforeKb: Long,
    ) {
        private var firstTokenAtMs: Long? = null
        private var peakRssKb: Long = rssBeforeKb
        private var tokenCount: Int = 0

        /** Call once per token streamed back from the model. */
        fun onToken() {
            if (firstTokenAtMs == null) firstTokenAtMs = clockMs()
            tokenCount++
            val rss = currentRssKb()
            if (rss > peakRssKb) peakRssKb = rss
        }

        /**
         * Close out the measurement and publish a [MetricRecord]. Safe to
         * call exactly once. Subsequent calls are no-ops.
         *
         * @param tokensOut override the token count — useful if the caller
         *   knows the exact output length (e.g. after a final detokenize
         *   pass) and the per-token streaming granularity differs.
         */
        fun finish(tokensOut: Int = tokenCount) {
            if (published) return
            val endMs = clockMs()
            val ttft = firstTokenAtMs?.let { it - startedAtMs }
            val totalMs = (endMs - startedAtMs).coerceAtLeast(1)
            val tps = if (tokensOut > 0) tokensOut.toDouble() * 1000.0 / totalMs else 0.0

            record(
                MetricRecord(
                    requestId = requestId,
                    tag = tag,
                    reasoning = reasoning,
                    ttftMs = ttft,
                    tokensOut = tokensOut,
                    tokensPerSec = tps,
                    rssBeforeKb = rssBeforeKb,
                    rssPeakKb = peakRssKb,
                    rssAfterKb = currentRssKb(),
                    thermal = currentThermal().wire,
                )
            )
            published = true
        }

        /** Abandon this probe (e.g. generation failed). Emits nothing. */
        fun abort() {
            published = true
        }

        private var published = false
    }

    companion object {
        private const val RECENT_CAP = 100

        private fun newRequestId(): String = java.util.UUID.randomUUID().toString()

        /**
         * Android-platform-backed factory. Reads thermal status from the
         * system [PowerManager].
         */
        fun create(logger: EidosLogger, powerManager: PowerManager): MetricsRecorder =
            MetricsRecorder(
                logger = logger,
                thermalStatusProvider = { powerManager.currentThermalStatus },
            )
    }
}

/**
 * Serializable metrics row. Public so R8 keeps it (see `proguard-rules.pro`).
 */
@Serializable
data class MetricRecord(
    val requestId: String,
    val tag: String,
    val reasoning: Boolean,
    val ttftMs: Long?,
    val tokensOut: Int,
    val tokensPerSec: Double,
    val rssBeforeKb: Long,
    val rssPeakKb: Long,
    val rssAfterKb: Long,
    val thermal: String,
)

/**
 * Mirror of [PowerManager.THERMAL_STATUS_*]. Stable wire names so log schema
 * survives Android API changes.
 */
enum class ThermalState(val wire: String) {
    NOMINAL("nominal"),
    LIGHT("light"),
    MODERATE("moderate"),
    SEVERE("severe"),
    CRITICAL("critical"),
    EMERGENCY("emergency"),
    SHUTDOWN("shutdown"),
    ;

    companion object {
        /** Map raw [PowerManager.THERMAL_STATUS_*] to a stable name. */
        fun fromPlatform(raw: Int): ThermalState = when (raw) {
            PowerManager.THERMAL_STATUS_NONE -> NOMINAL
            PowerManager.THERMAL_STATUS_LIGHT -> LIGHT
            PowerManager.THERMAL_STATUS_MODERATE -> MODERATE
            PowerManager.THERMAL_STATUS_SEVERE -> SEVERE
            PowerManager.THERMAL_STATUS_CRITICAL -> CRITICAL
            PowerManager.THERMAL_STATUS_EMERGENCY -> EMERGENCY
            PowerManager.THERMAL_STATUS_SHUTDOWN -> SHUTDOWN
            else -> NOMINAL
        }
    }
}

/**
 * Convenience wrapper so callers can pass structured `data` without importing
 * kotlinx.serialization.json themselves.
 */
fun diagData(block: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit): JsonElement =
    buildJsonObject(block)
