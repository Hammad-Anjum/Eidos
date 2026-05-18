import SwiftUI

struct StreamingText: View {
    let text: String
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            MarkdownText(markdown: text)
            if isStreaming {
                Text("●")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
            }
        }
    }
}
