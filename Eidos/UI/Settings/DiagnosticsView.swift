import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Developer-facing diagnostics panel. Exposed from Settings in DEBUG
/// builds, gated behind "5 taps on version number" in RELEASE.
///
/// Tabs:
///   - **Logs** — live JSONL tail, filterable by category / level.
///   - **Metrics** — last N generations in a table.
///   - **Benchmarks** — run the corpus, show results.
///   - **Flags** — toggle feature flags for live testing.
struct DiagnosticsView: View {

    @Environment(AppContainer.self) private var container
    @State private var section: Section = .logs

    enum Section: String, CaseIterable, Identifiable {
        case smokeTest, logs, metrics, benchmarks, flags, chats
        var id: String { rawValue }
        var label: String {
            switch self {
            case .smokeTest: "Smoke"
            case .logs: "Logs"
            case .metrics: "Metrics"
            case .benchmarks: "Benchmarks"
            case .flags: "Flags"
            case .chats: "Chats"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            Group {
                switch section {
                case .smokeTest: SmokeTestPane()
                case .logs: LogsPane()
                case .metrics: MetricsPane()
                case .benchmarks: BenchmarksPane()
                case .flags: FlagsPane()
                case .chats: ChatsPane()
                }
            }
        }
        .navigationTitle("Diagnostics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Smoke-test pane

/// Bypasses ChatViewModel and RAGPipeline entirely. Calls
/// `GemmaSession.generate(...)` directly with a hardcoded 4-token prompt
/// and shows the streamed result inline. If this works but the chat tab
/// still crashes, the bug is in our wrapper code (RAGPipeline,
/// ChatViewModel, SwiftData persistence). If this also crashes, the bug
/// is at the GemmaSession / mlx-swift layer.
///
/// Every step writes a breadcrumb to `EidosLogger`, so even if the smoke
/// test crashes the next launch's log tail tells us exactly where.
private struct SmokeTestPane: View {
    @Environment(AppContainer.self) private var container

    @State private var output: String = ""
    @State private var status: Status = .idle
    @State private var lastError: String?
    @State private var elapsedMs: Double?
    @State private var firstTokenMs: Double?

    private enum Status: Equatable {
        case idle, running, succeeded, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Direct Gemma smoke test")
                    .font(.title3.bold())

                Text("Bypasses chat, RAG, ambient, tools, and SwiftData. Calls Gemma directly with a tiny prompt. Use this when chat crashes — the result tells the developer where in the stack it died.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    runSmokeTest()
                } label: {
                    Label(
                        status == .running ? "Running…" : "Run smoke test",
                        systemImage: status == .running ? "hourglass" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(status == .running)

                if status == .succeeded {
                    Label("Gemma replied successfully", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout.bold())
                } else if status == .failed {
                    Label("Failed — see Logs tab for trace", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout.bold())
                }

                if let firstTokenMs {
                    LabeledContent("Time to first token", value: String(format: "%.0f ms", firstTokenMs))
                        .font(.caption.monospaced())
                }
                if let elapsedMs {
                    LabeledContent("Total time", value: String(format: "%.0f ms", elapsedMs))
                        .font(.caption.monospaced())
                }

                if !output.isEmpty {
                    Divider()
                    Text("Gemma output").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(output)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }

                if let lastError {
                    Divider()
                    Text("Error").font(.caption.bold()).foregroundStyle(.red)
                    Text(lastError)
                        .font(.callout.monospaced())
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
    }

    private func runSmokeTest() {
        status = .running
        output = ""
        lastError = nil
        elapsedMs = nil
        firstTokenMs = nil

        EidosLogger.shared.log(.info, category: .model, event: "smoketest.start",
            payload: ["bypass": "rag,chat,swiftdata"])
        let start = Date()

        Task { @MainActor in
            do {
                // Tiny prompt — same shape the briefing uses successfully.
                // No system bloat. Just a prove-Gemma-works smoke test.
                let messages: [[String: String]] = [
                    ["role": "user", "content": "Say hi in one short sentence."]
                ]
                let stream = try await container.gemma.generate(messages: messages)
                EidosLogger.shared.log(.info, category: .model, event: "smoketest.stream-acquired")

                var firstSeen: Date?
                for try await chunk in stream {
                    if firstSeen == nil {
                        firstSeen = Date()
                        firstTokenMs = firstSeen!.timeIntervalSince(start) * 1000
                        EidosLogger.shared.log(.info, category: .model, event: "smoketest.first-token",
                            payload: ["ms": firstTokenMs ?? 0])
                    }
                    output += chunk
                }
                let end = Date()
                elapsedMs = end.timeIntervalSince(start) * 1000
                status = .succeeded
                EidosLogger.shared.log(.info, category: .model, event: "smoketest.done",
                    payload: [
                        "chars": output.count,
                        "elapsed_ms": elapsedMs ?? 0,
                        "first_token_ms": firstTokenMs ?? 0,
                    ])
            } catch {
                lastError = String(describing: error)
                status = .failed
                EidosLogger.shared.error(.model, event: "smoketest.error",
                    error: error, failure: .modelGenerate)
            }
        }
    }
}

// MARK: - Logs pane

private struct LogsPane: View {
    @State private var entries: [EidosLogEntry] = []
    @State private var filterCategory: EidosLogCategory? = nil
    @State private var filterLevel: EidosLogLevel = .debug
    @State private var refreshToken = UUID()

    var body: some View {
        VStack {
            HStack {
                Picker("Category", selection: $filterCategory) {
                    Text("All").tag(nil as EidosLogCategory?)
                    ForEach(EidosLogCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(Optional(c))
                    }
                }
                .pickerStyle(.menu)

                Picker("Min level", selection: $filterLevel) {
                    ForEach(EidosLogLevel.allCases, id: \.self) { l in
                        Text(l.rawValue).tag(l)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button {
                    if let url = try? EidosLogger.shared.exportAll() {
                        share(url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .padding(.horizontal)

            List(filtered, id: \.timestamp) { entry in
                LogEntryRow(entry: entry)
            }
        }
        .onAppear { refresh() }
    }

    private var filtered: [EidosLogEntry] {
        entries.filter {
            $0.level >= filterLevel &&
            (filterCategory == nil || $0.category == filterCategory)
        }
    }

    private func refresh() {
        // 500 entries × ~1 KB each = ~500 KB resident. That's fine on a
        // phone with headroom; under memory pressure we drop to 100.
        // The logger files on disk are untouched — this is just the
        // in-memory tail we show in the UI.
        let limit = ProcessInfo.processInfo.physicalMemory < 6_000_000_000 ? 100 : 500
        entries = EidosLogger.shared.recentEntries(limit: limit)
    }

    private func share(_ url: URL) {
        #if canImport(UIKit)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?.present(av, animated: true)
        #endif
    }
}

private struct LogEntryRow: View {
    let entry: EidosLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.level.rawValue.uppercased())
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(levelColor)
                    .frame(width: 50, alignment: .leading)

                Text(entry.category.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(entry.timestamp.suffix(13).prefix(8))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Text(entry.event)
                .font(.caption.bold())

            if let msg = entry.message, !msg.isEmpty {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let failure = entry.failure {
                Text("fail: \(failure.displayLabel)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .blue
        case .warn: .orange
        case .error: .red
        case .metric: .green
        }
    }
}

// MARK: - Metrics pane

private struct MetricsPane: View {
    @State private var entries: [EidosLogEntry] = []
    @State private var decayReport: DecayReport?

    var body: some View {
        List {
            Section("Memory decay") {
                if let r = decayReport {
                    LabeledContent("Last pass", value: r.ranAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                    LabeledContent("Demoted", value: "\(r.demoted.count)")
                        .font(.caption.monospaced())
                    LabeledContent("Archived", value: "\(r.archived.count)")
                        .font(.caption.monospaced())
                    LabeledContent("Evicted", value: "\(r.evicted.count)")
                        .font(.caption.monospaced())
                    LabeledContent("Skipped (pinned)", value: "\(r.skippedPinned.count)")
                        .font(.caption.monospaced())
                } else {
                    Text("No decay pass has run yet on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Generation metrics") {
                if entries.isEmpty {
                    Text("No generation metrics yet. Send a chat message and come back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(entries, id: \.timestamp) { entry in
                    if entry.event == "generate" || entry.event == "generate.metrics" {
                        MetricRow(entry: entry)
                    }
                }
            }
        }
        .onAppear {
            entries = EidosLogger.shared.recentEntries(limit: 200).filter { $0.level == .metric }
            // ACTION-8 + NEXT-8: surface the latest persisted decay
            // report so users can see what's been happening to their
            // memories without watching the JSONL log directly.
            decayReport = MemoryDecayEngine.loadLatestReport()
        }
    }
}

private struct MetricRow: View {
    let entry: EidosLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.event).font(.caption.bold())
            if let p = entry.payload {
                let ttft = scalar(p["ttft_ms"])
                let tps = scalar(p["tok_per_sec"])
                let rss = scalar(p["rss_mb_peak"])
                let tok = scalar(p["tokens"])
                HStack(spacing: 14) {
                    Label("\(fmt(ttft)) ms", systemImage: "bolt")
                    Label("\(fmt(tps)) tok/s", systemImage: "gauge")
                    Label("\(fmt(rss)) MB", systemImage: "memorychip")
                    Label("\(fmt(tok)) tok", systemImage: "t.square")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func scalar(_ v: AnyCodableValue?) -> Double? {
        guard let v else { return nil }
        if case .double(let d) = v { return d }
        if case .int(let i) = v { return Double(i) }
        return nil
    }
    private func fmt(_ d: Double?) -> String {
        guard let d else { return "—" }
        return d >= 10 ? String(format: "%.0f", d) : String(format: "%.1f", d)
    }
}

// MARK: - Benchmarks pane

private struct BenchmarksPane: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        BenchmarkRunnerBody(runner: container.benchmarkRunner)
    }
}

private struct BenchmarkRunnerBody: View {
    @Bindable var runner: BenchmarkRunner
    @State private var reasoning: ReasoningMode = .fast

    var body: some View {
        VStack(spacing: 16) {
            if runner.isRunning {
                VStack(spacing: 8) {
                    ProgressView(value: runner.progress)
                    Text(runner.currentPromptID ?? "running…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            } else {
                Picker("Reasoning", selection: $reasoning) {
                    Text("Fast").tag(ReasoningMode.fast)
                    Text("Reasoning").tag(ReasoningMode.reasoning)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Button {
                    Task {
                        let flags = EidosFeatureFlags.shared
                        await runner.run(
                            visionAvailable: flags.visionEnabled,
                            audioAvailable: flags.audioViaGemmaEnabled && GemmaSession.supportsNativeAudioInput,
                            reasoning: reasoning
                        )
                    }
                } label: {
                    Label("Run benchmarks", systemImage: "stopwatch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }

            if let summary = runner.lastSummary {
                List {
                    Section("Summary") {
                        LabeledContent("Device", value: summary.deviceName)
                        LabeledContent("Prompts", value: "\(summary.totalPrompts)")
                        LabeledContent("Succeeded (≥0.6)", value: "\(summary.succeeded)")
                        LabeledContent("Avg score", value: String(format: "%.2f", summary.averageScore))
                        LabeledContent("Median TTFT", value: summary.medianTTFTms.map { String(format: "%.0f ms", $0) } ?? "—")
                        LabeledContent("Median tok/s", value: String(format: "%.1f", summary.medianTokensPerSecond))
                    }
                    Section("By category") {
                        ForEach(Array(summary.byCategory.keys.sorted()), id: \.self) { key in
                            if let cat = summary.byCategory[key] {
                                HStack {
                                    Text(key).font(.caption.monospaced())
                                    Spacer()
                                    Text(String(format: "%.2f", cat.averageScore))
                                        .font(.caption.monospaced().bold())
                                }
                            }
                        }
                    }
                    Section("Failures (<0.6)") {
                        ForEach(summary.results.filter { $0.score < 0.6 }, id: \.promptID) { r in
                            VStack(alignment: .leading) {
                                Text(r.promptID).font(.caption.bold())
                                Text(r.reason).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Chats pane

/// Shows every persisted `Conversation` and its `ConversationMessage`
/// rows. Primary use: "what did Eidos actually reply" when debugging a
/// bad response. Also useful as a trust artifact — users can audit
/// everything the model has ever told them.
private struct ChatsPane: View {
    @Environment(\.modelContext) private var modelContext
    @State private var conversations: [Conversation] = []
    @State private var selected: Conversation?

    var body: some View {
        Group {
            if conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("No conversations yet.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Send a chat message and come back.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let selected {
                ChatTranscriptView(conversation: selected) { self.selected = nil }
            } else {
                List(conversations) { c in
                    Button { selected = c } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(c.title).font(.body)
                                Spacer()
                                Text("\(c.messages.count)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(c.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        conversations = (try? modelContext.fetch(descriptor)) ?? []
    }
}

/// Displays one conversation's messages, newest at bottom, chat-style.
/// Includes an export button that serialises the thread to markdown
/// and hands it to the share sheet.
private struct ChatTranscriptView: View {
    let conversation: Conversation
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                Spacer()
                Text(conversation.title).font(.caption.bold())
                Spacer()
                Button {
                    share(exportAsMarkdown())
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let sortedMessages = conversation.messages
                        .sorted { $0.timestamp < $1.timestamp }
                    ForEach(sortedMessages) { m in
                        DiagnosticsMessageBubble(message: m)
                    }
                }
                .padding()
            }
        }
    }

    private func exportAsMarkdown() -> URL {
        var lines: [String] = []
        lines.append("# \(conversation.title)")
        lines.append("")
        lines.append("_\(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))_")
        lines.append("")
        for m in conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            lines.append("## \(m.role.capitalized) — \(m.timestamp.formatted(date: .omitted, time: .standard))")
            lines.append("")
            lines.append(m.content)
            lines.append("")
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eidos-chat-\(Int(Date().timeIntervalSince1970)).md")
        try? lines.joined(separator: "\n").write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    private func share(_ url: URL) {
        #if canImport(UIKit)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?.present(av, animated: true)
        #endif
    }
}

private struct DiagnosticsMessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.role.capitalized)
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(roleColor)
                Spacer()
                Text(message.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Text(message.content)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var roleColor: Color {
        switch message.role {
        case "user": .blue
        case "assistant", "model": .green
        case "system": .orange
        default: .secondary
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case "user": .blue.opacity(0.08)
        case "assistant", "model": .green.opacity(0.06)
        case "system": .orange.opacity(0.05)
        default: .secondary.opacity(0.08)
        }
    }
}

// MARK: - Flags pane

private struct FlagsPane: View {
    @Bindable var flags = EidosFeatureFlags.shared

    var body: some View {
        Form {
            Section("Capabilities") {
                Toggle("Vision (image input)", isOn: $flags.visionEnabled)
                Toggle("Audio capture pipeline", isOn: $flags.audioEnabled)
                Toggle("Audio via Gemma (bypass Speech)", isOn: $flags.audioViaGemmaEnabled)
                Toggle("Reasoning / chain-of-thought", isOn: $flags.reasoningEnabled)
                Toggle("Long-context memory packing", isOn: $flags.longContextPackingEnabled)
                Toggle("Personas (Phase 9)", isOn: $flags.personasEnabled)
            }
            Section {
                Toggle("Minimal chat prompt", isOn: $flags.minimalChatPromptEnabled)
            } header: {
                Text("Chat path")
            } footer: {
                Text("ON: chat uses a small briefing-size prompt — no RAG, no tools, no ambient. Required on iPhone today to keep the GPU prefill inside Metal's heap budget. Turn OFF to try the full pipeline (may crash on iPhone).")
                    .font(.caption2)
            }
            Section("UI") {
                Toggle("Diagnostics panel", isOn: $flags.diagnosticsUIEnabled)
            }
            Section("Safety") {
                Toggle("Safety gate (DEBUG only)", isOn: $flags.safetyGateEnabled)
                    .disabled(!isDebug)
                Text(isDebug
                    ? "Disabling safety gate is only allowed in DEBUG builds."
                    : "Safety gate is always ON in release builds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset all flags to defaults") { flags.resetAll() }
                    .foregroundStyle(.orange)
            }
        }
    }

    private var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
