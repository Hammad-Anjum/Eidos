import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity — renders in the Lock Screen expanded card and in the
/// Dynamic Island. The compact / minimal / expanded presentations are
/// the three "states" iOS cycles through depending on context.
struct DigestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DigestActivityAttributes.self) { context in
            // Lock-screen expanded card.
            LockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (when user long-presses the Dynamic Island).
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .font(.title2)
                        .foregroundStyle(iconGradient)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .meetingSoon, let start = context.state.startsAt {
                        Text(start, style: .relative)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(iconGradient)
            } compactTrailing: {
                if context.state.phase == .meetingSoon, let start = context.state.startsAt {
                    Text(start, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 40)
                } else {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(iconGradient)
            }
        }
    }

    private var iconGradient: AngularGradient {
        AngularGradient(
            colors: [
                .pink, .orange, .yellow, .mint, .cyan, .indigo, .purple, .pink,
            ],
            center: .center
        )
    }
}

// MARK: - Lock screen card

private struct LockScreenView: View {
    let state: DigestActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.symbolName)
                .font(.title)
                .foregroundStyle(
                    AngularGradient(
                        colors: [.pink, .orange, .yellow, .mint, .cyan, .indigo, .purple, .pink],
                        center: .center
                    )
                )
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if state.phase == .meetingSoon, let start = state.startsAt {
                Text(start, style: .relative)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
