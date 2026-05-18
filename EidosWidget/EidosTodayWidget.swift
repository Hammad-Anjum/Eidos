import WidgetKit
import SwiftUI
import AppIntents

/// Read-only Home Screen widget for Eidos.
///
/// Surfaces the same one-line agenda summary that the Home tab's
/// `TodayAgendaLine` renders, plus the most recent energy label and a
/// "Sit With Me" button that deep-links into the app. The widget never
/// writes — it only reads `EidosTodaySnapshot` from the App Group
/// container. The main app writes the snapshot when Home appears, so
/// the widget catches up next refresh.
///
/// Small + Medium families. No configuration, no parameters — keeps
/// the surface minimal and audience-friendly (no setup tax).
///
/// Note: this widget is additive. The existing Control Widgets
/// (`EidosTalkControl`, `EidosBriefingControl`) remain registered in
/// `EidosWidgetBundle` and work unchanged.
struct EidosTodayWidget: Widget {

    let kind: String = "com.hissamuddin.eidos.Widget.Today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EidosTodayProvider()) { entry in
            EidosTodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today on Eidos")
        .description("A one-line agenda summary, the most recent energy state, and one tap into Sit With Me.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline provider

struct EidosTodayEntry: TimelineEntry {
    let date: Date
    let snapshot: EidosTodaySnapshot
}

struct EidosTodayProvider: TimelineProvider {

    func placeholder(in context: Context) -> EidosTodayEntry {
        EidosTodayEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EidosTodayEntry) -> Void) {
        completion(EidosTodayEntry(date: Date(), snapshot: EidosTodaySnapshotStore.read()))
    }

    /// One entry now + one entry 30 minutes from now. The main app
    /// writes a fresh snapshot whenever the user opens Home; the
    /// 30-min ceiling is the fallback when the app stays closed.
    func getTimeline(in context: Context, completion: @escaping (Timeline<EidosTodayEntry>) -> Void) {
        let now = Date()
        let snapshot = EidosTodaySnapshotStore.read()
        let entries = [EidosTodayEntry(date: now, snapshot: snapshot)]
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - View

struct EidosTodayWidgetView: View {

    @Environment(\.widgetFamily) private var family
    let entry: EidosTodayEntry

    var body: some View {
        switch family {
        case .systemSmall:  smallBody
        case .systemMedium: mediumBody
        default:            smallBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 4)
            Text(entry.snapshot.agendaLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Spacer(minLength: 4)
                Text(entry.snapshot.agendaLine)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                footer
            }

            // Sit With Me deep-link button — visible only on the
            // medium family because the small family is too cramped
            // to render the affordance honestly.
            sitWithMeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Eidos · Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if !entry.snapshot.energyLabel.isEmpty {
                Label(entry.snapshot.energyLabel, systemImage: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if entry.snapshot.sessionsToday > 0 {
                Label("\(entry.snapshot.sessionsToday)", systemImage: "person.line.dotted.person.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var sitWithMeButton: some View {
        Link(destination: URL(string: "eidos://home")!) {
            VStack(spacing: 6) {
                Image(systemName: "person.line.dotted.person.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Sit With Me")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 88)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.45, green: 0.25, blue: 0.85),
                             Color(red: 0.30, green: 0.18, blue: 0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
    }
}
