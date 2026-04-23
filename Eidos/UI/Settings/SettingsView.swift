import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @Query private var entries: [KnowledgeEntry]

    @State private var digestEnabled = false
    @State private var digestTime: Date = {
        var c = DateComponents(); c.hour = 7; c.minute = 0
        return Calendar.current.date(from: c) ?? .now
    }()
    @State private var notifStatus: NotificationAuthStatus = .notDetermined
    @State private var healthGranted = false
    @State private var memoryCount = 0

    var body: some View {
        NavigationStack {
            Form {
                modelSection
                proactiveSection
                privacySection
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task { await loadState() }
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section("Model") {
            let variant = container.modelDownloader.selectedVariant
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.displayName)
                    Text(container.modelDownloader.isModelDownloaded
                        ? "Ready" : "Not downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: container.modelDownloader.isModelDownloaded
                      ? "checkmark.seal.fill" : "arrow.down.circle")
                    .foregroundStyle(container.modelDownloader.isModelDownloaded ? .green : .secondary)
            }
        }
    }

    private var proactiveSection: some View {
        Section("Proactive") {
            Toggle("Morning briefing notification", isOn: $digestEnabled)
                .onChange(of: digestEnabled) { _, newValue in
                    Task { await setDigestEnabled(newValue) }
                }

            if digestEnabled {
                DatePicker(
                    "Deliver at",
                    selection: $digestTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: digestTime) { _, newValue in
                    Task { await updateDigestTime(newValue) }
                }
            }

            if notifStatus == .denied {
                Label(
                    "Notifications disabled in iOS Settings.",
                    systemImage: "bell.slash"
                )
                .foregroundStyle(.orange)
                .font(.caption)
            }

            Button(healthGranted ? "Health access granted" : "Grant health access") {
                Task { await requestHealth() }
            }
            .disabled(healthGranted)
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("On-device only", systemImage: "lock.shield")
            Label("EgressGuard armed", systemImage: "network.slash")
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            LabeledContent("Knowledge base", value: "\(entries.count) entries")
            LabeledContent("Memory entries", value: "\(memoryCount)")
            Button("Run memory decay pass now") {
                Task { _ = try? await container.memoryDecayEngine.runOnce() }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–")
        }
    }

    // MARK: - Loading / actions

    private func loadState() async {
        digestEnabled = container.notificationScheduler.digestEnabled
        var c = DateComponents()
        c.hour = container.notificationScheduler.digestHour
        c.minute = container.notificationScheduler.digestMinute
        if let d = Calendar.current.date(from: c) { digestTime = d }
        notifStatus = await container.notificationScheduler.authorizationStatus()
        memoryCount = await container.memoryManager.index.count
        healthGranted = await container.healthSource.hasPermission
    }

    private func setDigestEnabled(_ on: Bool) async {
        container.notificationScheduler.digestEnabled = on
        if on, notifStatus == .notDetermined {
            _ = await container.notificationScheduler.requestPermission()
            notifStatus = await container.notificationScheduler.authorizationStatus()
        }
        await container.notificationScheduler.scheduleMorningDigest()
    }

    private func updateDigestTime(_ newTime: Date) async {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
        if let h = comps.hour { container.notificationScheduler.digestHour = h }
        if let m = comps.minute { container.notificationScheduler.digestMinute = m }
        await container.notificationScheduler.scheduleMorningDigest()
    }

    private func requestHealth() async {
        _ = await container.healthSource.requestPermission()
        healthGranted = await container.healthSource.hasPermission
    }
}
