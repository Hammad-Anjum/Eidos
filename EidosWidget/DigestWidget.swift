import WidgetKit
import SwiftUI

/// Eidos's morning-briefing widget. Renders the latest digest snapshot
/// that the main app wrote to the App Group. Refreshes every 30 minutes
/// — WidgetKit coalesces that with system budgeting so real frequency
/// may be lower, which is fine (digest changes once a day).
struct DigestWidget: Widget {
    let kind: String = "EidosDigestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DigestProvider()) { entry in
            DigestWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Eidos briefing")
        .description("Your morning briefing, at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Timeline

struct DigestEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDigestSnapshot
}

struct DigestProvider: TimelineProvider {
    func placeholder(in context: Context) -> DigestEntry {
        DigestEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DigestEntry) -> Void) {
        let snapshot = SharedStore.readDigest() ?? .placeholder
        completion(DigestEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestEntry>) -> Void) {
        let snapshot = SharedStore.readDigest() ?? .placeholder
        let entry = DigestEntry(date: Date(), snapshot: snapshot)
        // Re-read every 30 min. The main app also refreshes the widget
        // explicitly via `WidgetCenter.shared.reloadAllTimelines()` when
        // it writes a new digest, so this cadence is just a safety net.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
