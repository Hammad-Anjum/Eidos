import SwiftUI

/// Read/edit/delete a single memory entry. All mutations go through
/// `MemoryManager` so the decay index stays in sync.
struct MemoryEntryDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let recordID: UUID
    let onChange: () -> Void

    @State private var entry: MemoryEntry?
    @State private var editing = false
    @State private var draftBody = ""
    @State private var draftPriority: MemoryPriority = .p3
    @State private var draftTier: MemoryTier = .topic
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let entry {
                content(entry)
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(entry?.title ?? "Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await load() }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ entry: MemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            metaBlock(entry)
            Divider()
            if editing {
                editor
            } else {
                Text(entry.body)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }

    private func metaBlock(_ entry: MemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(tierLabel(entry.tier), systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                priorityPicker
            }
            Text(entry.updatedAt, format: .dateTime.month().day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
            if !entry.tags.isEmpty {
                tagCloud(entry.tags)
            }
        }
    }

    private func tagCloud(_ tags: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var priorityPicker: some View {
        Picker("Priority", selection: $draftPriority) {
            ForEach(MemoryPriority.allCases, id: \.self) { p in
                Text("P\(p.rawValue)").tag(p)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!editing)
        .frame(width: 200)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tier", selection: $draftTier) {
                ForEach(MemoryTier.allCases, id: \.self) { t in
                    Text(tierLabel(t)).tag(t)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $draftBody)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button("Save") { Task { await save() } }
            } else {
                Menu {
                    Button { beginEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button { Task { await touch() } } label: { Label("Mark as hot", systemImage: "flame") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        entry = try? await container.memoryManager.load(id: recordID)
        if let e = entry {
            draftBody = e.body
            draftPriority = e.priority
            draftTier = e.tier
        }
    }

    private func beginEdit() {
        guard let e = entry else { return }
        draftBody = e.body
        draftPriority = e.priority
        draftTier = e.tier
        editing = true
    }

    private func save() async {
        guard var e = entry else { return }
        e.body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        e.priority = draftPriority
        // Important: keep the entry at its ORIGINAL tier during save, so the
        // file is rewritten in place. If the user chose a different tier,
        // we move as a separate step — MemoryManager.move handles deleting
        // the old-tier file before writing the new one.
        let tierChanged = e.tier != draftTier

        do {
            _ = try await container.memoryManager.save(e)
            if tierChanged {
                try await container.memoryManager.move(id: e.id, to: draftTier)
            }
            editing = false
            await load()
            onChange()
        } catch {
            editing = false
        }
    }

    private func touch() async {
        try? await container.memoryManager.touch(id: recordID)
        await load()
        onChange()
    }

    private func performDelete() async {
        try? await container.memoryManager.delete(id: recordID)
        onChange()
        dismiss()
    }

    // MARK: - Labels

    private func tierLabel(_ tier: MemoryTier) -> String {
        switch tier {
        case .coreIdentity:     "Core identity"
        case .activePriorities: "Active priorities"
        case .topic:            "Topic"
        case .recentSession:    "Recent session"
        case .archive:          "Archive"
        }
    }
}
