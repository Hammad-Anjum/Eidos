import WidgetKit
import SwiftUI

/// Dispatches on widget family so we can render appropriate density.
struct DigestWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DigestEntry

    var body: some View {
        switch family {
        case .accessoryInline:      inlineView
        case .accessoryRectangular: accessoryRectangular
        case .systemMedium:         mediumView
        default:                    smallView
        }
    }

    // MARK: - Home Screen: small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("Eidos")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let event = entry.snapshot.nextEvent {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.start, style: .time)
                        .font(.title3.bold())
                    Text(event.title)
                        .font(.caption)
                        .lineLimit(2)
                }
            } else {
                Text(entry.snapshot.greeting)
                    .font(.title3.bold())
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                statBadge(icon: "calendar", count: entry.snapshot.eventsToday)
                statBadge(icon: "checklist", count: entry.snapshot.remindersOpen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Home Screen: medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(entry.snapshot.greeting)
                    .font(.headline)
                Spacer()
                Text(entry.snapshot.generatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.snapshot.briefing)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .lineLimit(4)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                statBadge(icon: "calendar", count: entry.snapshot.eventsToday, label: "events")
                statBadge(icon: "checklist", count: entry.snapshot.remindersOpen, label: "reminders")
                Spacer()
                if let event = entry.snapshot.nextEvent {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Next")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(event.start, style: .time)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Lock Screen: accessoryRectangular

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Eidos").font(.caption2.weight(.semibold))
            }
            if let event = entry.snapshot.nextEvent {
                Text(event.start, style: .time)
                    .font(.headline)
                Text(event.title)
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text(entry.snapshot.greeting)
                    .font(.headline)
                Text("\(entry.snapshot.eventsToday) events · \(entry.snapshot.remindersOpen) reminders")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Lock Screen: accessoryInline

    private var inlineView: some View {
        if let event = entry.snapshot.nextEvent {
            Label {
                Text("\(event.title) at \(event.start, style: .time)")
            } icon: {
                Image(systemName: "calendar")
            }
        } else {
            Label("\(entry.snapshot.eventsToday) events today", systemImage: "sparkles")
        }
    }

    // MARK: - Pieces

    private func statBadge(icon: String, count: Int, label: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
