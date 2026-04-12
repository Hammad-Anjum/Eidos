import SwiftUI

struct HomeView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Good morning")
                        .font(.largeTitle.bold())
                    Text("Your digest will appear here once the model is loaded.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Eidos")
        }
    }
}
