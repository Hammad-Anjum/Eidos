import SwiftUI

struct StreamingText: View {
    let text: String
    var isStreaming: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if isStreaming {
                Text("●")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
            }
        }
    }
}
