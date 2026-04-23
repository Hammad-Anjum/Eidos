import SwiftUI
import SwiftData

@main
struct EidosApp: App {

    @State private var container: AppContainer?
    @State private var initError: String?

    init() {
        do {
            _container = State(initialValue: try AppContainer())
        } catch {
            _initError = State(initialValue: error.localizedDescription)
        }
    }

    @State private var showFeatureTour = false

    var body: some Scene {
        WindowGroup {
            if let container {
                Group {
                    if container.isBootstrapped && container.modelDownloader.isModelDownloaded {
                        RootView()
                    } else if container.isBootstrapped {
                        OnboardingView()
                    } else {
                        ProgressView("Starting Eidos...")
                    }
                }
                .environment(container)
                .modelContainer(container.modelContainer)
                .task { await container.bootstrap() }
                .onChange(of: container.modelDownloader.isModelDownloaded) { _, ready in
                    if ready && !UserDefaults.standard.bool(forKey: FeatureTourView.seenKey) {
                        showFeatureTour = true
                    }
                }
                .sheet(isPresented: $showFeatureTour) {
                    FeatureTourView()
                        .interactiveDismissDisabled(false)
                }
                .onOpenURL { url in
                    // `eidos://chat`, `eidos://home`, etc. — used by the
                    // widget's control intents and App Intents.
                    guard url.scheme == "eidos" else { return }
                    let tab: AppTab = switch url.host {
                    case "chat": .chat
                    case "home": .home
                    case "memory": .memory
                    case "knowledge": .knowledgeBase
                    case "settings": .settings
                    default: .home
                    }
                    NotificationCenter.default.post(name: .eidosJumpToTab, object: tab)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Eidos failed to start.")
                        .font(.headline)
                    if let initError {
                        Text(initError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}
