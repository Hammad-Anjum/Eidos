import SwiftUI
import WidgetKit

/// Slim contextual "today" line for the Home tab.
///
/// Sits between the greeting and the Sit With Me hero. Surfaces up to
/// three facts in priority order:
///
///   1. **Next calendar event** within the next 4 hours — gives the
///      user a built-in stop signal during any session they start.
///   2. **Active priority count** — informational, not nag.
///   3. **Body-double sessions completed today** — quiet affirmation
///      without congratulation.
///
/// Empty state is gentle: *"Quiet day so far."* — never accusatory.
/// Reads from the existing `CalendarSource` + `MemoryManager.index`;
/// no new permissions, no new persistence. Refreshes once on appear;
/// the user can pull the tab down to re-fetch (handled by enclosing
/// Home scroll view if/when added — not yet).
struct TodayAgendaLine: View {

    @Environment(AppContainer.self) private var container

    @State private var line: String = "…"
    @State private var hasLoaded: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(line)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's update. \(line)")
        .task { await refresh() }
    }

    /// Pulls calendar + memory + body-double snapshots and composes
    /// up to three short facts into one line. Idempotent — calling
    /// repeatedly just refreshes the line.
    private func refresh() async {
        var parts: [String] = []

        // 1. Next calendar event within 4 hours, if any.
        let events = await container.calendarSource.fetchEvents(daysAhead: 1)
        if let next = events.first(where: { $0.startDate > Date() }) {
            let minutes = Int(next.startDate.timeIntervalSinceNow / 60)
            if minutes > 0 && minutes < 240 {
                parts.append("\(minutes) min before \(next.title)")
            }
        }

        // 2. Active priorities count.
        let priorities = await container.memoryManager.index.records(tier: .activePriorities)
        if !priorities.isEmpty {
            let noun = priorities.count == 1 ? "priority" : "priorities"
            parts.append("\(priorities.count) \(noun) open")
        }

        // 3. Body-double sessions completed today.
        let all = await container.memoryManager.index.all
        let todaySessions = all.filter {
            $0.tags.contains("body-double") &&
            Calendar.current.isDateInToday($0.updatedAt)
        }
        if !todaySessions.isEmpty {
            let noun = todaySessions.count == 1 ? "session" : "sessions"
            parts.append("\(todaySessions.count) \(noun) today")
        }

        line = parts.isEmpty ? "Quiet day so far." : parts.joined(separator: "  ·  ")
        hasLoaded = true

        // Hand a fresh snapshot to the App Group container + nudge
        // WidgetKit so the EidosTodayWidget catches up next render.
        // Cheap (small JSON write) and bounded by however often the
        // user opens Home, which is the right cadence for a widget
        // that summarizes "what's today shaped like."
        await writeWidgetSnapshot(
            agendaLine: line,
            priorityCount: priorities.count,
            sessionsToday: todaySessions.count
        )
    }

    /// Persists a `EidosTodaySnapshot` into the App Group container
    /// and reloads the widget timeline. All inputs come from `refresh()`
    /// — this just adds the energy label (from `@AppStorage`) and
    /// writes.
    @MainActor
    private func writeWidgetSnapshot(
        agendaLine: String,
        priorityCount: Int,
        sessionsToday: Int
    ) async {
        let energyLevel = UserDefaults.standard
            .object(forKey: "eidos.auadhd.energyLevel") as? Int ?? 2
        let energyLabel = HomeView.energyLabel(for: energyLevel)
        let snapshot = EidosTodaySnapshot(
            agendaLine: agendaLine,
            energyLabel: energyLabel,
            priorityCount: priorityCount,
            sessionsToday: sessionsToday,
            updatedAt: Date()
        )
        EidosTodaySnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.hissamuddin.eidos.Widget.Today")
    }
}
