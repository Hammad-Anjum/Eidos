import SwiftUI

/// "Today" section of the Memory tab — a low-effort daily recap.
///
/// AuDHD adults frequently lose the felt sense of "did I do anything
/// today" because burnout flattens days into one continuous fog. This
/// section is the antidote: a passive, zero-input view of everything
/// the user has touched since midnight, grouped by skill source so the
/// shapes of the day are legible at a glance.
///
/// Four buckets, each derived from existing `MemoryIndexRecord` data
/// without any new persistence:
///
///   - 🟣 **Body-double sessions** — entries tagged `body-double`
///   - 🔵 **Scenes broken down** — entries tagged `scene` or
///     `look-mode`
///   - 🟠 **Tasks picked**       — `activePriorities` entries whose
///     `lastAccessedAt` is today (the `PickNextTaskSkill` touches them)
///   - 📝 **Journal entries**     — entries tagged `journal`
///
/// "Today" is anchored to the user's current local calendar day
/// (`Calendar.current.startOfDay(for: Date())`), so a 12-day journal
/// session that started yesterday and ended this morning shows up
/// today — which matches how the audience actually experiences time.
///
/// Empty state is deliberately gentle: a single line acknowledging the
/// quiet, without any "you should have done more" framing. This
/// audience opts out of shame loops by design.
struct TodayThreadsSection: View {

    let records: [MemoryIndexRecord]

    /// Categories the daily recap groups by. Each carries its own
    /// `headline(count:)` so we control plurals at the source — generic
    /// pluralization (`+s`) butchers "scene broken downs" and
    /// "task pickeds."
    private enum BucketKind {
        case bodyDouble
        case scene
        case taskPicked
        case journal

        var icon: String {
            switch self {
            case .bodyDouble: "person.line.dotted.person.fill"
            case .scene:      "eye.fill"
            case .taskPicked: "checkmark.circle.fill"
            case .journal:    "mic.fill"
            }
        }

        var tint: Color {
            switch self {
            case .bodyDouble: .purple
            case .scene:      .blue
            case .taskPicked: .orange
            case .journal:    .pink
            }
        }

        func headline(count: Int) -> String {
            switch self {
            case .bodyDouble:
                count == 1 ? "1 body-double session"
                           : "\(count) body-double sessions"
            case .scene:
                count == 1 ? "1 scene broken down"
                           : "\(count) scenes broken down"
            case .taskPicked:
                count == 1 ? "1 task picked"
                           : "\(count) tasks picked"
            case .journal:
                count == 1 ? "1 journal entry"
                           : "\(count) journal entries"
            }
        }
    }

    private struct Bucket {
        let kind: BucketKind
        let entries: [MemoryIndexRecord]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if buckets.allSatisfy({ $0.entries.isEmpty }) {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                        if !bucket.entries.isEmpty {
                            bucketCard(bucket)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Bucket cards

    private func bucketCard(_ bucket: Bucket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: bucket.kind.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(bucket.kind.tint)
                    .frame(width: 22)
                Text(bucket.kind.headline(count: bucket.entries.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            // Show up to 3 representative titles, each with a leading
            // dot bullet. Anything more than 3 collapses into "+ N more"
            // so the day's shape stays visible without scrolling.
            ForEach(bucket.entries.prefix(3)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(displayLine(for: entry))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 32)
            }
            if bucket.entries.count > 3 {
                Text("+ \(bucket.entries.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quiet day so far.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Anything you sit with, photograph, journal, or pick will land here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bucketing

    private var buckets: [Bucket] {
        let today = todaysRecords
        return [
            Bucket(
                kind: .bodyDouble,
                entries: today.filter { $0.tags.contains("body-double") }
            ),
            Bucket(
                kind: .scene,
                entries: today.filter {
                    $0.tags.contains("scene") || $0.tags.contains("look-mode")
                }
            ),
            // Picked, not merely created. `touch(id:)` updates only
            // `lastAccessedAt`, never `updatedAt` — so a strict `>`
            // here excludes priorities that were just seeded or
            // edited today and were never actually selected by
            // `PickNextTaskSkill`. Without this guard, the demo's
            // pre-seeded fixtures all light up as "picked today" on
            // first launch.
            Bucket(
                kind: .taskPicked,
                entries: records.filter {
                    $0.tier == .activePriorities &&
                    Calendar.current.isDateInToday($0.lastAccessedAt) &&
                    $0.lastAccessedAt > $0.updatedAt
                }
            ),
            Bucket(
                kind: .journal,
                entries: today.filter { $0.tags.contains("journal") }
            ),
        ]
    }

    /// Anything updated *or* re-touched since midnight counts as today.
    /// `updatedAt` covers fresh creates; `lastAccessedAt` covers
    /// active-priorities touches by `PickNextTaskSkill`. We OR both so a
    /// priority that was created days ago but picked today still appears.
    private var todaysRecords: [MemoryIndexRecord] {
        records.filter {
            Calendar.current.isDateInToday($0.updatedAt) ||
            Calendar.current.isDateInToday($0.lastAccessedAt)
        }
    }

    // MARK: - Display helpers

    private func displayLine(for entry: MemoryIndexRecord) -> String {
        // Many title prefixes are templated (e.g. "Sat with — fold
        // laundry"). Strip the prefix so the recap reads as a list of
        // *what*, not a list of *what kind of what*.
        let stripPrefixes = [
            "Sat with — ",
            "Scene breakdown — ",
            "Journal — ",
        ]
        var line = entry.title
        for prefix in stripPrefixes where line.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count))
            break
        }
        return line
    }

}
