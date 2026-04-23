import Foundation
import SwiftData

/// Persists the conversation across app launches via SwiftData. Chat
/// state lives as one `Conversation` with a chain of `ConversationMessage`
/// rows. Crystallization runs only when the session had meaningful
/// substance (≥3 exchanges, ≥60s of activity) — cheap tab switches no
/// longer burn Gemma cycles.
@MainActor
@Observable
final class ChatViewModel {

    /// Plain value type used by the view. Decouples the UI from
    /// `@Model` identity, which matters for row diffing in SwiftUI.
    struct Message: Identifiable, Equatable {
        let id: UUID
        let role: String
        var content: String
        let timestamp: Date
    }

    // MARK: - Observable state

    var messages: [Message] = []
    var streamingBuffer = ""
    var isGenerating = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let pipeline: RAGPipeline
    private let crystallizer: MemoryCrystallizer
    private let modelContext: ModelContext

    // Per-session state the view can't see directly.
    private var conversation: Conversation?
    private var lastCrystallizedAt: Date?
    private var turnsSinceCrystallize = 0
    private let crystallizeMinTurns = 3
    private let crystallizeMinSeconds: TimeInterval = 60

    // MARK: - Init

    init(pipeline: RAGPipeline, crystallizer: MemoryCrystallizer, modelContext: ModelContext) {
        self.pipeline = pipeline
        self.crystallizer = crystallizer
        self.modelContext = modelContext
        loadOrStartConversation()
    }

    // MARK: - Conversation lifecycle

    /// Loads the most recent conversation so the user picks up where they
    /// left off. New installs start fresh.
    private func loadOrStartConversation() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            conversation = existing
            messages = existing.messages
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map { Message(id: $0.id, role: $0.role, content: $0.content, timestamp: $0.timestamp) }
        } else {
            let fresh = Conversation()
            modelContext.insert(fresh)
            try? modelContext.save()
            conversation = fresh
            messages = []
        }
    }

    /// Starts a brand-new conversation. The old one stays in storage —
    /// Phase 7+ can add a history browser.
    func newConversation() {
        // Crystallize the old session (if worth it) before switching.
        triggerCrystallization()
        let fresh = Conversation()
        modelContext.insert(fresh)
        try? modelContext.save()
        conversation = fresh
        messages = []
        turnsSinceCrystallize = 0
        lastCrystallizedAt = nil
    }

    // MARK: - Send

    func send(_ text: String) {
        let userRow = appendMessage(role: "user", content: text)
        streamingBuffer = ""
        isGenerating = true
        errorMessage = nil

        let history = messages.dropLast().map { (role: $0.role, content: $0.content) }

        Task {
            let assistantRow = appendMessage(role: "assistant", content: "")
            let assistantID = assistantRow.id

            do {
                let stream = try await pipeline.chat(userMessage: text, history: history)
                for try await token in stream {
                    streamingBuffer += token
                    // Look up the message by id each tick — if the user
                    // started a new conversation mid-stream, messages may
                    // have been reset and the row is gone. Skip instead
                    // of crashing with an out-of-bounds write.
                    if let i = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[i].content = streamingBuffer
                    }
                }
                updatePersisted(id: assistantID, content: streamingBuffer)
                turnsSinceCrystallize += 1
            } catch {
                errorMessage = UserFacingError.message(for: error)
                updatePersisted(id: assistantID, content: streamingBuffer)
            }

            streamingBuffer = ""
            isGenerating = false
            _ = userRow  // referenced for clarity
        }
    }

    // MARK: - End of session (called from ChatView.onDisappear)

    /// Guarded crystallization — only runs if the session had real
    /// substance and enough time has passed since the last pass.
    func endSession() {
        triggerCrystallization()
    }

    private func triggerCrystallization() {
        guard turnsSinceCrystallize >= crystallizeMinTurns else { return }
        if let last = lastCrystallizedAt,
           Date().timeIntervalSince(last) < crystallizeMinSeconds { return }
        let snapshot = messages.map { (role: $0.role, content: $0.content) }
        guard !snapshot.isEmpty else { return }

        lastCrystallizedAt = Date()
        turnsSinceCrystallize = 0

        Task.detached(priority: .utility) { [crystallizer] in
            _ = try? await crystallizer.crystallize(conversation: snapshot)
        }
    }

    // MARK: - Persistence helpers

    @discardableResult
    private func appendMessage(role: String, content: String) -> Message {
        let row = ConversationMessage(role: role, content: content)
        conversation?.messages.append(row)
        conversation?.updatedAt = Date()
        try? modelContext.save()
        let value = Message(id: row.id, role: row.role, content: row.content, timestamp: row.timestamp)
        messages.append(value)
        return value
    }

    private func updatePersisted(id: UUID, content: String) {
        guard let row = conversation?.messages.first(where: { $0.id == id }) else { return }
        row.content = content
        conversation?.updatedAt = Date()
        try? modelContext.save()
    }
}
