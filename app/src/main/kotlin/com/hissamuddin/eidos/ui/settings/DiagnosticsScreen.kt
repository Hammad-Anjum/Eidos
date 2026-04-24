package com.hissamuddin.eidos.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.hissamuddin.eidos.R
import com.hissamuddin.eidos.platform.diagnostics.BenchmarkReport
import com.hissamuddin.eidos.platform.diagnostics.BenchmarkRunner
import com.hissamuddin.eidos.platform.diagnostics.EidosFeatureFlags
import com.hissamuddin.eidos.platform.diagnostics.EidosLogger
import com.hissamuddin.eidos.platform.diagnostics.LogRecord
import com.hissamuddin.eidos.platform.diagnostics.MetricRecord
import com.hissamuddin.eidos.platform.diagnostics.MetricsRecorder
import com.hissamuddin.eidos.ui.LocalAppContainer
import kotlinx.coroutines.launch

/**
 * Four-tab diagnostics view:
 *  - Logs: live tail of [EidosLogger.logStream]
 *  - Metrics: recent per-generation metrics from [MetricsRecorder.recent]
 *  - Benchmarks: run the corpus via [BenchmarkRunner] and show results
 *  - Flags: toggle every entry in [EidosFeatureFlags]
 *
 * This screen is the A0 milestone proof: if it renders and the "Run
 * Benchmarks" button produces a populated report, the diagnostics stack is
 * wired end-to-end.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiagnosticsScreen(onBack: () -> Unit) {
    val container = LocalAppContainer.current

    var selectedTab by remember { mutableStateOf(DiagnosticsTab.LOGS) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_diagnostics_label)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            TabRow(selectedTabIndex = selectedTab.ordinal) {
                DiagnosticsTab.entries.forEach { tab ->
                    Tab(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        text = { Text(stringResource(tab.titleRes)) },
                    )
                }
            }
            when (selectedTab) {
                DiagnosticsTab.LOGS -> LogsTab(container.logger)
                DiagnosticsTab.METRICS -> MetricsTab(container.metrics)
                DiagnosticsTab.BENCHMARKS -> BenchmarksTab(container.benchmarkRunner)
                DiagnosticsTab.FLAGS -> FlagsTab(container.flags)
            }
        }
    }
}

private enum class DiagnosticsTab(val titleRes: Int) {
    LOGS(R.string.diagnostics_tab_logs),
    METRICS(R.string.diagnostics_tab_metrics),
    BENCHMARKS(R.string.diagnostics_tab_benchmarks),
    FLAGS(R.string.diagnostics_tab_flags),
}

// --- Logs -------------------------------------------------------------------

@Composable
private fun LogsTab(logger: EidosLogger) {
    // Accumulate the tail as it streams. `remember(logger)` re-runs if the
    // logger identity changes (never does in normal flow).
    val entries = remember(logger) { mutableStateListOf<LogRecord>() }
    LaunchedEffect(logger) {
        logger.logStream.collect { rec ->
            entries.add(0, rec)
            if (entries.size > MAX_LOG_TAIL) entries.removeAt(entries.lastIndex)
        }
    }

    if (entries.isEmpty()) {
        EmptyState(stringResource(R.string.diagnostics_empty_logs))
        return
    }

    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(entries, key = { it.ts + it.msg }) { rec ->
            LogRow(rec)
        }
    }
}

@Composable
private fun LogRow(rec: LogRecord) {
    val levelColor = when (rec.level) {
        "error" -> MaterialTheme.colorScheme.error
        "warn" -> MaterialTheme.colorScheme.tertiary
        "metric" -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    ListItem(
        overlineContent = {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text(
                    text = rec.level.uppercase(),
                    color = levelColor,
                    style = MaterialTheme.typography.labelMedium,
                )
                Spacer(Modifier.width(8.dp))
                Text(rec.category, style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.width(8.dp))
                Text(rec.ts.takeLast(12), style = MaterialTheme.typography.labelMedium)
            }
        },
        headlineContent = {
            Text(
                text = rec.msg,
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.bodyLarge,
            )
        },
    )
}

// --- Metrics ----------------------------------------------------------------

@Composable
private fun MetricsTab(metrics: MetricsRecorder) {
    val recent by metrics.recent.collectAsState()
    if (recent.isEmpty()) {
        EmptyState(stringResource(R.string.diagnostics_empty_metrics))
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(recent, key = { it.requestId }) { m -> MetricRow(m) }
    }
}

@Composable
private fun MetricRow(m: MetricRecord) {
    ListItem(
        overlineContent = {
            Text(
                text = "${m.tag} • ${m.thermal}",
                style = MaterialTheme.typography.labelMedium,
            )
        },
        headlineContent = {
            Text(
                text = "%d tok • %.1f tok/s • ttft %s".format(
                    m.tokensOut,
                    m.tokensPerSec,
                    m.ttftMs?.let { "${it}ms" } ?: "—",
                ),
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.bodyLarge,
            )
        },
        supportingContent = {
            Text(
                text = "rss %d→%d→%d kB".format(m.rssBeforeKb, m.rssPeakKb, m.rssAfterKb),
                style = MaterialTheme.typography.labelMedium,
            )
        },
    )
}

// --- Benchmarks -------------------------------------------------------------

@Composable
private fun BenchmarksTab(runner: BenchmarkRunner) {
    val scope = rememberCoroutineScope()
    val progress by runner.progress.collectAsState()
    val report by runner.report.collectAsState()

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        if (progress.total > 0) {
            Text(
                text = "Running ${progress.currentId} (${progress.current + 1} / ${progress.total})",
                style = MaterialTheme.typography.bodyLarge,
            )
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { (progress.current.toFloat() / progress.total.coerceAtLeast(1)).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            Button(
                onClick = { scope.launch { runner.runAll() } },
                enabled = true,
            ) {
                Text(stringResource(R.string.diagnostics_run_benchmarks))
            }
        }

        Spacer(Modifier.height(16.dp))

        report?.let { ReportSummary(it) }
    }
}

@Composable
private fun ReportSummary(report: BenchmarkReport) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = "Total ${report.total} — passed ${report.passed} — failed ${report.failed}",
            style = MaterialTheme.typography.titleLarge,
        )
        Spacer(Modifier.height(8.dp))
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(report.results, key = { it.id }) { result ->
                ListItem(
                    overlineContent = {
                        Text(
                            text = "${result.category} • ${if (result.passed) "PASS" else "FAIL"}",
                            color = if (result.passed) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                    headlineContent = {
                        Text(result.id, style = MaterialTheme.typography.bodyLarge)
                    },
                    supportingContent = {
                        Text(
                            text = result.failureMsg
                                ?: result.output.take(120).ifBlank { "(empty output)" },
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                )
            }
        }
    }
}

// --- Flags ------------------------------------------------------------------

@Composable
private fun FlagsTab(flags: EidosFeatureFlags) {
    val scope = rememberCoroutineScope()
    val entries = remember(flags) {
        listOf(
            FlagBinding("Vision", flags.visionEnabled) { flags.setVisionEnabled(it) },
            FlagBinding("Audio via Gemma", flags.audioViaGemmaEnabled) { flags.setAudioViaGemmaEnabled(it) },
            FlagBinding("Audio capture", flags.audioEnabled) { flags.setAudioEnabled(it) },
            FlagBinding("Reasoning (CoT)", flags.reasoningEnabled) { flags.setReasoningEnabled(it) },
            FlagBinding("Personas", flags.personasEnabled) { flags.setPersonasEnabled(it) },
            FlagBinding("Diagnostics UI", flags.diagnosticsUiEnabled) { flags.setDiagnosticsUiEnabled(it) },
            FlagBinding("Long-context packing", flags.longContextPackingEnabled) {
                flags.setLongContextPackingEnabled(it)
            },
            FlagBinding("Safety gate (release-locked)", flags.safetyGateEnabled) {
                flags.setSafetyGateEnabled(it)
            },
            FlagBinding("Notification listener", flags.notificationListenerEnabled) {
                flags.setNotificationListenerEnabled(it)
            },
            FlagBinding("Foreground service", flags.foregroundServiceEnabled) {
                flags.setForegroundServiceEnabled(it)
            },
        )
    }

    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(entries, key = { it.label }) { entry ->
            val value by entry.flow.collectAsState(initial = false)
            ListItem(
                headlineContent = { Text(entry.label) },
                trailingContent = {
                    Switch(
                        checked = value,
                        onCheckedChange = { next -> scope.launch { entry.setter(next) } },
                    )
                },
            )
        }
    }
}

private data class FlagBinding(
    val label: String,
    val flow: kotlinx.coroutines.flow.Flow<Boolean>,
    val setter: suspend (Boolean) -> Unit,
)

// --- Empty state ------------------------------------------------------------

@Composable
private fun EmptyState(text: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Transparent),
        contentAlignment = androidx.compose.ui.Alignment.Center,
    ) {
        Text(text = text, style = MaterialTheme.typography.bodyLarge)
    }
}

private const val MAX_LOG_TAIL = 500
