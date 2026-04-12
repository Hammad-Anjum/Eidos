import SwiftUI
import SwiftData

@main
struct EidosApp: App {

    @State private var container: AppContainer?
    @State private var initError: String?

    init() {
        // B14 / A3-asset: EgressGuard is NOT installed here. The container's
        // bootstrap() runs the NLContextualEmbedding asset download first
        // (which legitimately needs Apple's CDN), then arms the guard. This
        // is safe because no URLSession traffic happens before bootstrap()
        // executes inside the root view's .task modifier.
        do {
            let container = try AppContainer()
            _container = State(initialValue: container)
        } catch {
            _initError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .environment(container)
                    .task { await container.bootstrap() }
            } else {
                VStack(spacing: 8) {
                    Text("Eidos failed to start.")
                        .font(.headline)
                    if let initError {
                        Text(initError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}
