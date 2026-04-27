import SwiftUI

/// User-facing window into everything Eidos remembers. Group by tier,
/// filter by search, tap through to edit/delete/change priority.
/// Crucial for trust — "remembers everything" is only OK if you can
/// audit it.
struct MemoryBrowserView: View {
    @Environment(AppContainer.self) private var container

    @State private var records: [MemoryIndexRecord] = []
    @State private var searchText = ""
    @State private var selectedTier: MemoryTier? = nil
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && records.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if records.isEmpty {
                    ContentUnavailableView(
                        "No memories yet",
                        systemImage: "brain",
                        description: Text("Chat with Eidos — the end-of-session crystallizer will start filling this in.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Memory")
            .searchable(text: $searchText, prompt: "Search")
            .toolbar { toolbar }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
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
        records = await container.memoryManager.index.all
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
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
}
