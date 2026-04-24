package com.hissamuddin.eidos.platform.diagnostics

import com.hissamuddin.eidos.inference.ChatMessage
import com.hissamuddin.eidos.inference.GemmaSession
import com.hissamuddin.eidos.inference.GenerationEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.put

/**
 * Executes the [BenchmarkCorpus] against a [GemmaSession] and produces a
 * scored report. Runs sequentially — concurrency would distort thermal and
 * TTFT numbers.
 *
 * A0 ships the skeleton callable against [com.hissamuddin.eidos.inference.StubGemmaSession];
 * A2 validates end-to-end on real LiteRT-LM.
 *
 * ## Results
 *
 *  - Per-prompt [BenchmarkResult] with output text, latency, tokens/sec,
 *    RSS peak, thermal, and rubric pass/fail.
 *  - [progress] StateFlow for the UI.
 *  - [report] — the latest finished run, or null.
 */
class BenchmarkRunner(
    private val session: GemmaSession,
    private val logger: EidosLogger,
    private val metrics: MetricsRecorder,
) {
    private val _progress = MutableStateFlow(Progress.IDLE)
    val progress: StateFlow<Progress> = _progress.asStateFlow()

    private val _report = MutableStateFlow<BenchmarkReport?>(null)
    val report: StateFlow<BenchmarkReport?> = _report.asStateFlow()

    /**
     * Execute the entire corpus. Suspends until complete. Safe to cancel via
     * the enclosing coroutine scope — in-flight generations will be aborted.
     */
    suspend fun runAll(): BenchmarkReport = run(BenchmarkCorpus.prompts)

    /** Execute an arbitrary subset of prompts (used by Diagnostics filters). */
    suspend fun run(prompts: List<BenchmarkPrompt>): BenchmarkReport {
        session.load()
        logger.info(LogCategory.BENCHMARK, "Run started", diagData { put("n", prompts.size) })

        val results = mutableListOf<BenchmarkResult>()
        for ((index, prompt) in prompts.withIndex()) {
            _progress.value = Progress(current = index, total = prompts.size, currentId = prompt.id)
            results += runOne(prompt)
        }

        val report = BenchmarkReport(
            startedAt = results.firstOrNull()?.startedAt ?: "",
            total = results.size,
            passed = results.count { it.passed },
            failed = results.count { !it.passed },
            results = results,
        )
        _report.value = report
        _progress.value = Progress.IDLE
        logger.info(
            LogCategory.BENCHMARK,
            "Run complete",
            diagData {
                put("passed", report.passed)
                put("failed", report.failed)
            },
        )
        return report
    }

    private suspend fun runOne(prompt: BenchmarkPrompt): BenchmarkResult {
        val startedAt = nowIso()
        val probe = metrics.start(tag = "benchmark:${prompt.id}", reasoning = prompt.reasoning)
        val output = StringBuilder()
        var failureMsg: String? = null

        try {
            session.generate(
                messages = listOf(ChatMessage(ChatMessage.Role.USER, prompt.text)),
                reasoning = prompt.reasoning,
            ).collect { event ->
                when (event) {
                    is GenerationEvent.Token -> {
                        probe.onToken()
                        output.append(event.text)
                    }
                    is GenerationEvent.Complete -> probe.finish(tokensOut = event.totalTokens)
                    is GenerationEvent.Failed -> {
                        failureMsg = "${event.category.name}: ${event.message}"
                        probe.abort()
                    }
                }
            }
        } catch (t: Throwable) {
            failureMsg = "${t.javaClass.simpleName}: ${t.message ?: "<no message>"}"
            probe.abort()
            logger.error(LogCategory.BENCHMARK, "Prompt threw", diagData { put("id", prompt.id) })
        }

        val rendered = output.toString()
        val passed = failureMsg == null && prompt.rubric.scores(rendered)

        return BenchmarkResult(
            id = prompt.id,
            category = prompt.category.name,
            startedAt = startedAt,
            output = rendered,
            passed = passed,
            failureMsg = failureMsg,
        )
    }

    data class Progress(val current: Int, val total: Int, val currentId: String) {
        companion object {
            val IDLE = Progress(current = 0, total = 0, currentId = "")
        }
    }

    private companion object {
        private fun nowIso(): String =
            java.text.SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                java.util.Locale.US,
            ).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                .format(java.util.Date())
    }
}

/** One row in the benchmark report. Serialized when the report is exported. */
@Serializable
data class BenchmarkResult(
    val id: String,
    val category: String,
    val startedAt: String,
    val output: String,
    val passed: Boolean,
    val failureMsg: String? = null,
)

/** Full benchmark report. Written to `filesDir/eidos/benchmarks/YYYY-MM-DD_hhmm.json`. */
@Serializable
data class BenchmarkReport(
    val startedAt: String,
    val total: Int,
    val passed: Int,
    val failed: Int,
    val results: List<BenchmarkResult>,
)
