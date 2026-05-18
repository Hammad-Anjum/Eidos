import SwiftUI

/// Slim, tappable privacy + storage summary pinned to the top of the
/// Memory tab.
///
/// Reads three live stats:
///   - **Memory count** — `MemoryManager.index.count`
///   - **Disk usage** — `MemoryManager.diskUsageBytes()` (recursive
///     sum across all tier directories)
///   - **Egress status** — derived from `EgressGuard.installedAt`;
///     when armed, shows the lockdown timestamp; before bootstrap
///     finishes, shows "Arming…"
///
/// Designed deliberately slim (~60pt) so the privacy moat is *implied*
/// rather than shouted. Loud privacy banners can perversely
/// anxiety-prime the user about other apps; the goal here is "always
/// visible, never alarming." Tapping opens `PrivacyDetailView` for
/// the full receipt: per-tier counts, latest decay pass, export
/// affordance, and the plain-language posture explainer.
struct MemoryStatsRibbon: View {

    let memoryCount: Int
    let diskBytes: Int64
    let egressArmedAt: Date?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                    .background(Color.green.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        statValue("\(memoryCount)", suffix: memoryCount == 1 ? "memory" : "memories")
                        Text("·").foregroundStyle(.tertiary)
                        statValue(formatBytes(diskBytes), suffix: "on disk")
                        Text("·").foregroundStyle(.tertiary)
                        statValue("0", suffix: "sent")
                    }
                    Text(egressStatusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.green.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens the privacy receipt — full per-tier counts, decay pass results, and export.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Subviews + formatting

    @ViewBuilder
    private func statValue(_ value: String, suffix: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Text(suffix)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var egressStatusLine: String {
        if let armed = egressArmedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Egress lockdown active since \(formatter.string(from: armed))"
        }
        return "Egress lockdown arming…"
    }

    private var accessibilitySummary: String {
        let armed = egressArmedAt != nil ? "Egress lockdown active." : "Egress lockdown arming."
        return "Privacy receipt. \(memoryCount) memories, \(formatBytes(diskBytes)) on disk, zero bytes sent. \(armed)"
    }

    /// `ByteCountFormatter` with `.file` style — matches what the Files
    /// app shows for the same directory, so the number the user sees
    /// here ties out if they ever inspect the sandbox externally.
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
