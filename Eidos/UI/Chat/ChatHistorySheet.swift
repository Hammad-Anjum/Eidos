import SwiftUI
import SwiftData

/// Lists every persisted `Conversation` in reverse-chronological order
/// so the user can resume a previous chat or just re-read what Eidos
/// said last week. Surfaced from the `ChatView` toolbar (clock arrow
/// icon). Tapping a row dismisses the sheet and asks `ChatViewModel`
/// to load that conversation.
///
/// This was previously only reachable through the Diagnostics panel,
/// which hides chat history from non-developer users. v10 makes it a
/// first-class entry point in the chat UI.
struct ChatHistorySheet: View {
    /// The conversation currently active in `ChatView` — highlighted
    /// in the list so the user knows which row matches what they were
    /// just looking at.
    let currentConversationID: UUID?

    /// Called with the user's selection. The caller is responsible
    /// for switching the active conversation and dismissing the sheet.
    let onSelect: (Conversation) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(conversations) { c in
                            row(for: c)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(c)
                                }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chat history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for c: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.title)
                    .font(.body.weight(c.id == currentConversationID ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if c.id == currentConversationID {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            HStack(spacing: 8) {
                Text(c.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(c.messages.count) message\(c.messages.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let preview = previewLine(for: c) {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    /// First non-empty user message, used as a one-line preview.
    /// Empty assistant bubbles (mid-stream crashes from older builds)
    /// shouldn't be the preview text — they'd just look like blanks.
    private func previewLine(for c: Conversation) -> String? {
        c.messages
            .sorted { $0.timestamp < $1.timestamp }
            .first(where: { $0.role == "user" && !$0.content.isEmpty })?
            .content
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            modelContext.delete(conversations[idx])
        }
        try? modelContext.save()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No chats yet")
                .font(.title3.bold())
            Text("Send your first message and it'll show up here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
