import SwiftUI

/// User-facing window into everything Eidos remembers.
///
/// Layout (2026-05-18 hybrid restructure):
///   1. **Privacy ribbon** — slim, tappable; opens `PrivacyDetailView`
///      sheet with the full per-tier breakdown, decay pass, export,
///      and posture explainer.
///   2. **Today section** — daily recap grouped by skill source
///      (body-double / scene / task-pick / journal). Empty-state is
///      gentle, never accusatory.
///   3. **All memories** — the original tier-grouped browser, fully
///      preserved: search, swipe-to-delete, run-decay menu, export.
///
/// The ribbon + today + browser ordering is intentional: privacy as
/// implied chrome (always-present, calm), today as the warm content
/// the user reaches for, browser as the exhaustive fallback. Each
/// answers a different mental question without competing for the same
/// "what is this tab for" cognitive slot.
struct MemoryBrowserView: View {
    @Environment(AppContainer.self) private var container

    @State private var records: [MemoryIndexRecord] = []
    @State private var searchText = ""
    @State private var selectedTier: MemoryTier? = nil
    @State private var isLoading = false
    @State private var diskBytes: Int64 = 0
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Memory")
                .searchable(text: $searchText, prompt: "Search")
                .toolbar { toolbar }
                .task { await reload() }
                .refreshable { await reload() }
                .sheet(isPresented: $showPrivacy) {
                    PrivacyDetailView()
                        .environment(container)
                }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            // Privacy ribbon — always present, regardless of search
            // state. The "0 memories" empty case still needs it so the
            // first-launch user sees the moat without the browser
            // crowding the screen.
            Section {
                MemoryStatsRibbon(
                    memoryCount: records.count,
                    diskBytes: diskBytes,
                    egressArmedAt: EgressGuard.installedAt
                ) {
                    showPrivacy = true
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            // Today section — only show when search is inactive.
            // Searching is a "find a specific past thing" action; the
            // today recap would just visually noise the search results.
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    TodayThreadsSection(records: records)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            // All memories — the exhaustive tier-grouped browser, the
            // original Memory tab content. Preserved so power-user
            // affordances (swipe-to-delete, per-entry detail) survive
            // the restructure.
            if records.isEmpty && !isLoading {
                Section {
                    ContentUnavailableView(
                        "No memories yet",
                        systemImage: "brain",
                        description: Text("Chat with Eidos, journal a thought, or sit through a body-double session — they'll all land here.")
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(MemoryTier.allCases, id: \.self) { tier in
                    let matching = filtered.filter { $0.tier == tier }
                    if !matching.isEmpty {
                        Section(sectionTitle(for: tier)) {
                            ForEach(matching) { rec in
                                NavigationLink {
                                    MemoryEntryDetailView(recordID: rec.id) {
                                        Task { await reload() }
                                    }
                                } label: {
                                    row(rec)
                                }
                            }
                            .onDelete { offsets in
                                Task { await delete(in: matching, offsets: offsets) }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ rec: MemoryIndexRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rec.title)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                priorityBadge(rec.priority)
            }
            HStack(spacing: 6) {
                Text(rec.lastAccessedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !rec.tags.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(rec.tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func priorityBadge(_ priority: MemoryPriority) -> some View {
        Text("P\(priority.rawValue)")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.15))
            .foregroundStyle(priorityColor(priority))
            .clipShape(Capsule())
    }

    private func priorityColor(_ p: MemoryPriority) -> Color {
        switch p {
        case .p1: .red
        case .p2: .orange
        case .p3: .blue
        case .p4: .gray
        case .p5: .secondary
        }
    }

    private func sectionTitle(for tier: MemoryTier) -> String {
        switch tier {
        case .coreIdentity:     "Core identity"
        case .activePriorities: "Active priorities"
        case .topic:            "Topics"
        case .recentSession:    "Recent sessions"
        case .archive:          "Archive"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Task { await exportWeeklySummary() }
                } label: {
                    Label("Share weekly summary", systemImage: "doc.text")
                }
                Button {
                    Task {
                        _ = try? await container.memoryDecayEngine.runOnce()
                        await reload()
                    }
                } label: {
                    Label("Run decay pass", systemImage: "wind")
                }
                Button {
                    Task { await export() }
                } label: {
                    Label("Export memory", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Data

    private var filtered: [MemoryIndexRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return records }
        return records.filter {
            $0.title.lowercased().contains(q)
                || $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private func reload() async {
        isLoading = true
        async let recordsTask = container.memoryManager.index.all
        async let bytesTask = container.memoryManager.diskUsageBytes()
        let (loaded, bytes) = await (recordsTask, bytesTask)
        records = loaded.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        diskBytes = bytes
        isLoading = false
    }

    private func delete(in matching: [MemoryIndexRecord], offsets: IndexSet) async {
        for index in offsets {
            let rec = matching[index]
            try? await container.memoryManager.delete(id: rec.id)
        }
        await reload()
    }

    @MainActor
    private func export() async {
        guard let zipURL = await MemoryExporter.exportAsZip(manager: container.memoryManager) else { return }
        // Present share sheet via UIActivityViewController bridge.
        MemoryExporter.share(zipURL)
    }

    /// Builds + shares a 7-day deterministic markdown summary.
    ///
    /// The summary lives at `tmp/eidos-weekly-YYYY-MM-DD.md`; the iOS
    /// share sheet picks the destination (Mail, Messages, Files,
    /// Print, etc.) so Eidos itself never sends. EgressGuard remains
    /// armed throughout — the user is the network here.
    ///
    /// Body-double entries are loaded from disk because their per-
    /// session duration lives in the markdown body, not the index.
    /// All other sections render from the in-memory index for speed
    /// and for the privacy posture (less data hot in memory = less
    /// data potentially leaked by a future bug).
    @MainActor
    private func exportWeeklySummary() async {
        let memory = container.memoryManager
        let allRecords = await memory.index.all
        let bodyDoubleIDs = allRecords
            .filter { $0.tags.contains("body-double") }
            .map { $0.id }

        var bodyDoubleEntries: [MemoryEntry] = []
        for id in bodyDoubleIDs {
            if let entry = try? await memory.load(id: id) {
                bodyDoubleEntries.append(entry)
            }
        }

        let bytes = await memory.diskUsageBytes()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        let inputs = WeeklySummaryBuilder.Inputs(
            records: allRecords,
            bodyDoubleEntries: bodyDoubleEntries,
            memoryCount: allRecords.count,
            diskBytes: bytes,
            weekEnding: Date(),
            egressArmedAt: EgressGuard.installedAt,
            appVersion: version,
            appBuild: build
        )
        let markdown = WeeklySummaryBuilder.build(inputs: inputs)

        do {
            let url = try WeeklySummaryBuilder.writeToTempFile(markdown, weekEnding: Date())
            MemoryExporter.share(url)
        } catch {
            EidosLogger.shared.error(
                .memory,
                event: "memory.weekly-summary.write-failed",
                error: error, failure: .memoryWrite
            )
        }
    }
}
