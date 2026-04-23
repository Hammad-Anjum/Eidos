import SwiftUI

struct ChatView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @State private var vm: ChatViewModel?
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            // Soft gradient background so the bubble feed doesn't float in a void.
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Ambient rainbow glow that pulses behind everything when
            // Gemma is thinking. Apple-Intelligence-style.
            AIAmbientGlow(active: vm?.isGenerating == true)

            VStack(spacing: 0) {
                if let vm {
                    messageList(vm)
                    ChatInputBar(
                        text: $input,
                        focused: $inputFocused,
                        isGenerating: vm.isGenerating
                    ) {
                        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        input = ""
                        vm.send(text)
                    }
                }
            }
        }
        .navigationTitle("Eidos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { container.appActionRegistry.pending.first },
            set: { _ in }
        )) { action in
            ActionConfirmationSheet(
                action: action,
                registry: container.appActionRegistry
            )
        }
        .onAppear {
            if vm == nil {
                vm = ChatViewModel(
                    pipeline: container.ragPipeline,
                    crystallizer: container.memoryCrystallizer,
                    modelContext: modelContext
                )
            }
        }
        .onDisappear { vm?.endSession() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm?.newConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("New conversation")
            }
        }
    }

    // MARK: - Message list

    @ViewBuilder
    private func messageList(_ vm: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if vm.messages.isEmpty {
                        emptyState
                    }
                    ForEach(vm.messages) { msg in
                        messageBubble(
                            msg,
                            isStreaming: vm.isGenerating
                                && msg.id == vm.messages.last?.id
                                && msg.role == "assistant"
                        )
                        .id(msg.id)
                    }
                    if let err = vm.errorMessage {
                        errorBubble(err)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 4)
            }
            .onChange(of: vm.messages.count) {
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: vm.streamingBuffer) {
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tint.opacity(0.8))
                .symbolEffect(.pulse, options: .repeating)
            Text("Chat with Eidos")
                .font(.title2.weight(.semibold))
            Text("Your private AI assistant.\nAsk anything. Everything stays on your device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 8) {
                Label("Try one of these", systemImage: "lightbulb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                suggestionChip("What's on my calendar today?")
                suggestionChip("Remind me to call Mom tomorrow at 3pm")
                suggestionChip("I'm vegetarian and I love Thai food")
            }
            .padding(.vertical, 8)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            input = text
            inputFocused = true
        } label: {
            HStack {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bubbles

    private func messageBubble(_ msg: ChatViewModel.Message, isStreaming: Bool) -> some View {
        HStack(alignment: .bottom) {
            if msg.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
                Group {
                    if isStreaming && !msg.content.isEmpty {
                        StreamingText(text: msg.content, isStreaming: true)
                    } else {
                        Text(msg.content)
                    }
                }
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(msg.role == "user" ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground(for: msg.role))
                .clipShape(bubbleShape(for: msg.role))

                if msg.role != "user" {
                    Text(msg.timestamp, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                }
            }

            if msg.role != "user" { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private func bubbleBackground(for role: String) -> some View {
        if role == "user" {
            LinearGradient(
                colors: [.accentColor, Color.accentColor.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.secondarySystemBackground)
        }
    }

    private func bubbleShape(for role: String) -> some Shape {
        if role == "user" {
            return UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18)
        } else {
            return UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18)
        }
    }

    // MARK: - Error

    private func errorBubble(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(err)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
