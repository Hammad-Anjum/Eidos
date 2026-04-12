import SwiftUI

struct KBBrowserView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Knowledge base is empty",
                systemImage: "books.vertical",
                description: Text("Voice notes, shared content, and imports will appear here.")
            )
            .navigationTitle("Knowledge")
        }
    }
}
