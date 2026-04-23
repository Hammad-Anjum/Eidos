import SwiftUI
import SwiftData

struct KBEntryDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: KnowledgeEntry
    @State private var editing = false
    @State private var draft: String = ""
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metaHeader
                Divider()
                if editing {
                    TextEditor(text: $draft)
                        .font(.body)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                } else {
                    Text(entry.content)
                        .textSelection(.enabled)
                }
                if !entry.tags.isEmpty { tagCloud }
            }
            .padding()
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from your knowledge base and its embeddings. Can't be undone.")
        }
    }

    // MARK: - Header

    private var metaHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.entrySource.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.createdAt, format: .dateTime.month().day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var tagCloud: some View {
        HStack(spacing: 6) {
            ForEach(entry.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button("Save") { save() }
                    .disabled(draft == entry.content)
            } else {
                Menu {
                    Button { beginEdit() } label: { Label("Edit", systemImage: "pencil") }
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

    private func beginEdit() {
        draft = entry.content
        editing = true
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.content else {
            editing = false
            return
        }
        entry.content = trimmed
        entry.contentHash = KnowledgeEntry.hash(of: trimmed)
        try? modelContext.save()
        editing = false
    }

    private func performDelete() {
        Task {
            try? await container.knowledgeRepo.delete(entry)
            await MainActor.run { dismiss() }
        }
    }
}
