import Foundation
import SwiftData
import CoreGraphics

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
    private let crystallizeMinTurns = 2  // lowered from 3 — a 2-turn chat with a real fact is worth crystallizing
    private let crystallizeMinSeconds: TimeInterval = 30  // lowered from 60 — bias toward more frequent memory writes

    /// Read-only id of the currently-active conversation. Surfaced so
    /// the History sheet can highlight which thread the user is in.
    var currentConversationID: UUID? { conversation?.id }

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
    /// `ChatHistoryView` lets users revisit prior conversations.
    ///
    /// Refuses to switch if a generation is in flight — switching mid-
    /// stream would tear down SwiftData rows the streaming Task is
    /// still appending tokens to, which has caused intermittent
    /// crashes. The button is also disabled in the UI while
    /// `isGenerating == true`, but this guard is a belt-and-braces
    /// safeguard for any other call sites.
    func newConversation() {
        guard !isGenerating else {
            EidosLogger.shared.log(.warn, category: .chat,
                event: "newConversation.blocked.generating",
                message: "Refused to start a new conversation while a generation was in flight.",
                failure: nil)
            return
        }

        // Crystallize the old session (if worth it) before switching.
        // The crystallizer itself runs Gemma — keep it detached so the
        // UI tap doesn't block on inference.
        triggerCrystallization()

        let fresh = Conversation()
        modelContext.insert(fresh)
        try? modelContext.save()
        conversation = fresh
        messages = []
        streamingBuffer = ""
        errorMessage = nil
        turnsSinceCrystallize = 0
        lastCrystallizedAt = nil

        EidosLogger.shared.log(.info, category: .chat, event: "newConversation.created",
            payload: ["conversation_id": fresh.id.uuidString])
    }

    /// Loads a previously-stored conversation back into the active view.
    /// Used by the History tab so users can resume where they left off
    /// (or just re-read old replies). Same `isGenerating` guard as
    /// `newConversation()` to avoid tearing down state mid-stream.
    func resumeConversation(_ target: Conversation) {
        guard !isGenerating else {
            EidosLogger.shared.log(.warn, category: .chat,
                event: "resumeConversation.blocked.generating")
            return
        }
        triggerCrystallization()
        conversation = target
        messages = target.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .map { Message(id: $0.id, role: $0.role, content: $0.content, timestamp: $0.timestamp) }
        streamingBuffer = ""
        errorMessage = nil
        turnsSinceCrystallize = 0
        lastCrystallizedAt = nil
        EidosLogger.shared.log(.info, category: .chat, event: "resumeConversation.loaded",
            payload: ["conversation_id": target.id.uuidString, "messages": messages.count])
    }

    // MARK: - Send

    /// Sends a user turn, optionally with attached image/audio media.
    /// The media flows through the pipeline to Gemma's multimodal path
    /// when the current model bridge supports it.
    ///
    /// Streaming applies a small **flush interval** (~60 ms) before
    /// pushing buffered tokens into the assistant bubble. Without it
    /// every single token triggered a SwiftUI redraw of the bubble
    /// list + ScrollView reflow + ambient-glow recomputation, which
    /// starved the MainActor enough during heavy generations that
    /// the iOS process watchdog killed Eidos with no Swift error to
    /// catch. 60 ms still feels like real-time streaming to the eye
    /// (~16 fps) but cuts SwiftUI work by 10-20×.
    func send(
        _ text: String,
        displayText: String? = nil,
        image: CGImage? = nil,
        audio: Data? = nil
    ) {
        let displayText = displayText ?? defaultDisplayText(for: text, image: image, audio: audio)
        let userRow = appendMessage(role: "user", content: displayText)
        streamingBuffer = ""
        isGenerating = true
        errorMessage = nil

        let history = messages.dropLast().map { (role: $0.role, content: $0.content) }

        Task {
            let assistantRow = appendMessage(role: "assistant", content: "")
            let assistantID = assistantRow.id

            // Token batcher: accumulates raw chunks from MLX and only
            // mutates the @Observable `messages[i].content` at most
            // once per `flushIntervalNs` (60 ms). Each mutation is one
            // SwiftUI invalidation; without batching we were doing
            // 50-150 invalidations per second and the actor scheduler
            // couldn't keep up.
            let flushIntervalNs: UInt64 = 60_000_000  // 60 ms
            var pendingFlushAt: UInt64 = DispatchTime.now().uptimeNanoseconds + flushIntervalNs
            var sawFirstToken = false

            // Local helper that writes the streaming buffer into the
            // bubble. Skips silently if the row has been cleared
            // (e.g. user tapped New Conversation mid-stream).
            let pushToBubble: () -> Void = { [weak self] in
                guard let self else { return }
                if let i = self.messages.firstIndex(where: { $0.id == assistantID }) {
                    self.messages[i].content = self.streamingBuffer
                }
            }

            do {
                let stream = try await pipeline.chat(
                    userMessage: text,
                    history: history,
                    image: image,
                    audio: audio
                )
                for try await token in stream {
                    if !sawFirstToken {
                        sawFirstToken = true
                        EidosLogger.shared.log(.info, category: .chat,
                            event: "chat.first-token-received",
                            payload: ["chunk_chars": token.count])
                    }
                    streamingBuffer += token
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now >= pendingFlushAt {
                        pushToBubble()
                        pendingFlushAt = now + flushIntervalNs
                    }
                }
                // Final flush so the last few tokens don't sit invisibly.
                pushToBubble()
                updatePersisted(id: assistantID, content: streamingBuffer)
                turnsSinceCrystallize += 1
                EidosLogger.shared.log(.info, category: .chat, event: "chat.send.done",
                    payload: ["chars": streamingBuffer.count, "saw_first_token": sawFirstToken])
            } catch is CancellationError {
                // Stream was cancelled — usually the user starting a new
                // conversation or switching tabs. Not an error from the
                // user's perspective; just stop quietly.
                pushToBubble()
                updatePersisted(id: assistantID, content: streamingBuffer)
                EidosLogger.shared.log(.info, category: .chat, event: "chat.send.cancelled",
                    payload: ["chars": streamingBuffer.count])
            } catch {
                // Any other error surfaces in the chat as an error
                // bubble + populates the assistant row with a clear
                // message instead of leaving an empty bubble. This is
                // the visible-failure-instead-of-silent-empty contract
                // the README promises.
                let userMessage = UserFacingError.message(for: error)
                errorMessage = userMessage
                if streamingBuffer.isEmpty {
                    streamingBuffer = "(generation failed: \(userMessage))"
                }
                pushToBubble()
                updatePersisted(id: assistantID, content: streamingBuffer)
                EidosLogger.shared.error(.chat, event: "chat.send.error",
                    error: error, failure: .modelGenerate)
            }

            streamingBuffer = ""
            isGenerating = false
            _ = userRow  // referenced for clarity
        }
    }

    private func defaultDisplayText(for text: String, image: CGImage?, audio: Data?) -> String {
        let markers = [image != nil ? "📷" : nil, audio != nil ? "🎙️" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        guard !markers.isEmpty else { return text }
        if text.isEmpty {
            switch (image != nil, audio != nil) {
            case (true, true):
                return "📷 🎙️ Image and voice note attached"
            case (true, false):
                return "📷 Image attached"
            case (false, true):
                return "🎙️ Voice note attached"
            default:
                return ""
            }
        }
        return "\(text)  \(markers)"
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
