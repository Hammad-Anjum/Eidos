import SwiftUI

enum AppTab: Hashable {
    case home
    case chat
    case memory
    case knowledgeBase
    case ingest
    case settings
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
}

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: Bindable(router).selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "sun.max") }
                .tag(AppTab.home)

            NavigationStack {
                ChatView()
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            .tag(AppTab.chat)

            MemoryBrowserView()
                .tabItem { Label("Memory", systemImage: "brain") }
                .tag(AppTab.memory)

            KBBrowserView()
                .tabItem { Label("Knowledge", systemImage: "books.vertical") }
                .tag(AppTab.knowledgeBase)

            IngestView()
                .tabItem { Label("Ingest", systemImage: "tray.and.arrow.down") }
                .tag(AppTab.ingest)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .eidosJumpToTab)) { note in
            if let tab = note.object as? AppTab {
                withAnimation { router.selectedTab = tab }
            }
        }
    }
}
