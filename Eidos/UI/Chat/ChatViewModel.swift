import Foundation

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ConversationMessage] = []
    var streamingBuffer = ""
    var isGenerating = false
    var errorMessage: String?

    private let pipeline: RAGPipeline

    init(pipeline: RAGPipeline) {
        self.pipeline = pipeline
    }

    func send(_ text: String) {
        // TODO(phase 3): incremental persistence during streaming (B10)
    }
}
