package com.hissamuddin.eidos

import android.app.Application
import android.content.Context
import android.os.PowerManager
import com.hissamuddin.eidos.inference.GemmaSession
import com.hissamuddin.eidos.inference.StubGemmaSession
import com.hissamuddin.eidos.platform.diagnostics.BenchmarkRunner
import com.hissamuddin.eidos.platform.diagnostics.EidosFeatureFlags
import com.hissamuddin.eidos.platform.diagnostics.EidosLogger
import com.hissamuddin.eidos.platform.diagnostics.LogCategory
import com.hissamuddin.eidos.platform.diagnostics.MetricsRecorder

/**
 * Application entry point + dependency graph root.
 *
 * Manual DI (no Hilt): we stay in charge of every construction call for
 * clarity at solo-dev scale and to avoid KSP compile-time overhead on a
 * hackathon schedule.
 *
 * Access from Compose via [LocalAppContainer]; access from a Context-bound
 * site via [Context.appContainer].
 */
class App : Application() {

    /** Created lazily on first access so onCreate stays cheap. */
    val container: AppContainer by lazy { AppContainer.create(this) }

    override fun onCreate() {
        super.onCreate()
        // Force-touch the container so the logger + flags exist by the time
        // any Activity starts. Keeps the first-log timestamp honest.
        container.logger.info(
            category = LogCategory.LIFECYCLE,
            msg = "Application onCreate",
        )
    }
}

/**
 * Dependency graph for A0. Each phase extends this as new subsystems land:
 *  - A1: knowledgeRepository, embeddingService
 *  - A2: swap StubGemmaSession for LiteRtGemmaSession
 *  - A3: memoryManager, ragPipeline
 *  - etc.
 */
class AppContainer(
    val logger: EidosLogger,
    val metrics: MetricsRecorder,
    val flags: EidosFeatureFlags,
    val gemmaSession: GemmaSession,
    val benchmarkRunner: BenchmarkRunner,
) {
    companion object {
        fun create(context: Context): AppContainer {
            val logger = EidosLogger.create(context)
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val metrics = MetricsRecorder.create(logger, pm)
            val flags = EidosFeatureFlags.create(context)

            // A0: stub inference so the benchmark harness is callable.
            // A2 replaces this with LiteRtGemmaSession.
            val gemma: GemmaSession = StubGemmaSession()

            val benchmarkRunner = BenchmarkRunner(
                session = gemma,
                logger = logger,
                metrics = metrics,
            )

            return AppContainer(
                logger = logger,
                metrics = metrics,
                flags = flags,
                gemmaSession = gemma,
                benchmarkRunner = benchmarkRunner,
            )
        }
    }
}

/** Context extension for non-Compose call sites that need the container. */
val Context.appContainer: AppContainer
    get() = (applicationContext as App).container
