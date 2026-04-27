import SwiftUI
import SwiftData

struct KBBrowserView: View {
    @Environment(AppContainer.self) private var container

    @Query(sort: \KnowledgeEntry.createdAt, order: .reverse)
    private var entries: [KnowledgeEntry]

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Knowledge base is empty",
                        systemImage: "books.vertical",
                        description: Text("Voice notes, shared content, and imports will appear here.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filtered) { entry in
                            NavigationLink {
                                KBEntryDetailView(entry: entry)
                            } label: {
                                KBRow(entry: entry)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Knowledge")
            .searchable(text: $searchText, prompt: "Search your notes")
        }
    }

    private var filtered: [KnowledgeEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.content.localizedCaseInsensitiveContains(q) }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { filtered[$0] }
        Task {
            for entry in targets {
                try? await container.knowledgeRepo.delete(entry)
            }
        }
    }
}

// MARK: - Row

private struct KBRow: View {
    let entry: KnowledgeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.entrySource.badgeLabel, systemImage: entry.entrySource.badgeIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.createdAt, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.content)
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Source badges

private extension EntrySource {
    var badgeLabel: String {
        switch self {
        case .calendar:        "Calendar"
        case .contact:         "Contact"
        case .note:            "Note"
        case .voice:           "Voice"
        case .whatsappExport:  "WhatsApp"
        case .mailExport:      "Mail"
        case .webClip:         "Web"
        case .manual:          "Manual"
        case .skillOutput:     "Skill"
        case .shareExtension:  "Shared"
        }
    }

    var badgeIcon: String {
        switch self {
        case .calendar:        "calendar"
        case .contact:         "person.crop.circle"
        case .note:            "note.text"
        case .voice:           "waveform"
        case .whatsappExport:  "bubble.left.and.bubble.right"
        case .mailExport:      "envelope"
        case .webClip:         "link"
        case .manual:          "square.and.pencil"
        case .skillOutput:     "wrench.and.screwdriver"
        case .shareExtension:  "square.and.arrow.up"
        }
    }
}
