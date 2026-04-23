import SwiftUI

struct MessageBubble: View {
    let role: String
    let content: String

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(content)
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
