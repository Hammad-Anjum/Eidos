import SwiftUI

struct IngestView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No pending items",
                systemImage: "tray",
                description: Text("Share content from any app to add it here.")
            )
            .navigationTitle("Ingest")
        }
    }
}
