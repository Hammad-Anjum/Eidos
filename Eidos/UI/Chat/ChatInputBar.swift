import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    let isGenerating: Bool
    let onSend: () -> Void

    var body: some View {
        HStack {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(isGenerating)
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(text.isEmpty || isGenerating)
        }
        .padding()
    }
}
