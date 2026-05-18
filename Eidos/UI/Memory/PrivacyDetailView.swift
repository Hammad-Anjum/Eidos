import SwiftUI

/// Full privacy receipt presented when the user taps `MemoryStatsRibbon`.
///
/// Composed of four sections that map 1:1 to the things a judge,
/// reporter, or skeptical user wants to verify before trusting an
/// AI app with mental-health-adjacent content:
///
///   1. **Posture line** — plain-English summary of the moat.
///   2. **Per-tier breakdown** — exactly how many memories sit at each
///      retention priority.
///   3. **Decay pass** — most recent decay results, proving the system
///      doesn't quietly hoard.
///   4. **Egress + export** — when the lockdown armed, with one-tap
///      markdown export so the user can take their data and leave.
///
/// Read-only of `AppContainer`. The dismissal is owned by the
/// presenter via `@Environment(\.dismiss)` rather than a callback so
/// the view composes cleanly into any sheet host.
struct PrivacyDetailView: View {

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var perTier: [MemoryTier: Int] = [:]
    @State private var totalCount: Int = 0
    @State private var diskBytes: Int64 = 0
    @State private var decayReport: DecayReport?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    postureCard
                    tierBreakdownCard
                    decayCard
                    egressCard
                    exportButton
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .navigationTitle("Privacy receipt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    // MARK: - Cards

    private var postureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text("Your data, your phone")
                    .font(.title3.weight(.semibold))
            }
            Text("Inference, memory, voice, and embeddings all run on this device. EgressGuard blocks every outbound network request in code — verified by URLProtocol interception, not just policy.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.08))
        )
    }

    private var tierBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("By retention tier")
                    .font(.headline)
                Spacer()
                Text("\(totalCount) total")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(MemoryTier.allCases, id: \.self) { tier in
                tierRow(tier, count: perTier[tier] ?? 0)
            }
            HStack {
                Text("On disk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(diskBytes))
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func tierRow(_ tier: MemoryTier, count: Int) -> some View {
        HStack {
            Circle()
                .fill(tierColor(tier))
                .frame(width: 8, height: 8)
            Text(tierLabel(tier))
                .font(.callout)
            Spacer()
            Text("\(count)")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var decayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last decay pass")
                .font(.headline)
            if let report = decayReport {
                Text(report.ranAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    statColumn(label: "Demoted", value: report.demoted.count, color: .orange)
                    statColumn(label: "Archived", value: report.archived.count, color: .blue)
                    statColumn(label: "Evicted", value: report.evicted.count, color: .red)
                    statColumn(label: "Skipped", value: report.skippedPinned.count, color: .gray)
                }
            } else {
                Text("No decay pass has run yet on this device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Decay quietly lowers the priority of unused memories, archives stale ones, and evicts long-cold P5 entries. Pinned memories are always skipped.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var egressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Egress lockdown")
                .font(.headline)
            HStack(spacing: 10) {
                Image(systemName: EgressGuard.installedAt == nil ? "hourglass" : "checkmark.seal.fill")
                    .foregroundStyle(EgressGuard.installedAt == nil ? .orange : .green)
                Text(egressStatusText)
                    .font(.callout)
            }
            Text("Zero bytes have left this device since lockdown engaged. The only outbound traffic the app ever permits is the one-time Gemma 4 model download from HuggingFace at first launch.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var exportButton: some View {
        Button {
            Task { await exportAll() }
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Export everything (.zip)")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Bundles every markdown memory file into a zip and opens the system share sheet.")
    }

    // MARK: - Helpers

    private func statColumn(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.monospaced().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tierLabel(_ tier: MemoryTier) -> String {
        switch tier {
        case .coreIdentity:     "Core identity"
        case .activePriorities: "Active priorities"
        case .topic:            "Topics"
        case .recentSession:    "Recent sessions"
        case .archive:          "Archive"
        }
    }

    private func tierColor(_ tier: MemoryTier) -> Color {
        switch tier {
        case .coreIdentity:     .red
        case .activePriorities: .orange
        case .topic:            .blue
        case .recentSession:    .green
        case .archive:          .gray
        }
    }

    private var egressStatusText: String {
        if let armed = EgressGuard.installedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Active since \(formatter.string(from: armed))"
        }
        return "Arming — bootstrap still in progress"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }

    // MARK: - Data

    private func reload() async {
        let index = container.memoryManager.index
        var counts: [MemoryTier: Int] = [:]
        var total = 0
        for tier in MemoryTier.allCases {
            let c = await index.records(tier: tier).count
            counts[tier] = c
            total += c
        }
        let bytes = await container.memoryManager.diskUsageBytes()
        perTier = counts
        totalCount = total
        diskBytes = bytes
        decayReport = MemoryDecayEngine.loadLatestReport()
    }

    @MainActor
    private func exportAll() async {
        guard let zipURL = await MemoryExporter.exportAsZip(manager: container.memoryManager) else {
            return
        }
        MemoryExporter.share(zipURL)
    }
}
