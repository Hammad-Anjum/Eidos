import SwiftUI

struct ChatView: View {
    @Environment(AppContainer.self) private var container
    @State private var vm: ChatViewModel?
    @State private var input = ""

    var body: some View {
        VStack {
            Spacer()
            Text("Chat with Eidos")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .navigationTitle("Eidos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if vm == nil {
                vm = ChatViewModel(pipeline: container.ragPipeline)
            }
        }
    }
}
