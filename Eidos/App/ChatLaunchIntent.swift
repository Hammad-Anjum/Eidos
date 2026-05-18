import CoreGraphics
import Foundation

/// One-shot signal that a Home tile (or some other surface) wants to
/// open the chat tab and immediately dispatch a turn.
///
/// `HomeView` writes a `ChatLaunchIntent` into
/// `AppContainer.pendingChatLaunch` and posts the
/// `.eidosJumpToTab` notification with `.chat`. `ChatView` consumes
/// the intent in `.onAppear` + `.onChange(of: container.pendingChatLaunch?.id)`
/// — it calls `ChatViewModel.send(...)` with the prompt/image, then
/// clears the intent so it doesn't fire again on the next re-render.
///
/// Identity (`id`) is the trigger: `.onChange` of the id fires even
/// when two consecutive intents happen to have identical prompts.
struct ChatLaunchIntent: Equatable {

    /// Unique trigger ID. SwiftUI `.onChange(of:)` keys off this so
    /// consecutive identical prompts still re-dispatch.
    let id: UUID

    /// The actual prompt text sent to Gemma. Should match one of the
    /// trigger phrases in `PromptTemplates.systemPrompt`'s AuADHD
    /// addendum so the right tool / behavior fires.
    let prompt: String

    /// What appears in the user's chat bubble. If nil, falls back to
    /// `prompt` (or "(photo)" if an image is attached).
    let displayText: String?

    /// Optional image attachment for multimodal vision turns
    /// (Look mode). The chat layer's `send(image:)` parameter eats
    /// this through `RAGPipeline.chat(image:)` → `MLXVLM`.
    let image: CGImage?

    /// When `true` (default), the chat layer fires `send(...)`
    /// immediately on consumption. When `false`, the prompt is
    /// (future) populated into the input field for the user to edit
    /// before sending.
    let autoSend: Bool

    init(
        prompt: String,
        displayText: String? = nil,
        image: CGImage? = nil,
        autoSend: Bool = true
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.displayText = displayText
        self.image = image
        self.autoSend = autoSend
    }

    /// Equality keys off `id` only — two intents are "the same" iff
    /// they share an id. This keeps `.onChange(of:)` semantics tight.
    static func == (lhs: ChatLaunchIntent, rhs: ChatLaunchIntent) -> Bool {
        lhs.id == rhs.id
    }
}
