import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    Text("Gemma 4 E4B")
                    Text("Not yet downloaded")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Section("Privacy") {
                    Label("On-device only", systemImage: "lock.shield")
                    Label("Egress guard: active", systemImage: "network.slash")
                }
                Section("Storage") {
                    Text("Knowledge base: 0 entries")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
