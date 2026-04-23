import SwiftUI

struct HomeView: View {
    @Environment(AppContainer.self) private var container
    @State private var vm: HomeViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                timeGradient.ignoresSafeArea()
                ScrollView {
                    if let vm {
                        content(vm)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if vm == nil {
                vm = HomeViewModel(
                    generator: container.proactiveDigestGenerator,
                    calendarSource: container.calendarSource,
                    healthSource: container.healthSource,
                    notificationScheduler: container.notificationScheduler,
                    liveActivityManager: container.liveActivityManager
                )
                Task { await vm?.refresh() }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            digestCard(vm)
            if let signals = vm.signals, !signals.nudges.isEmpty {
                nudgesCard(signals.nudges)
            }
            quickActionsGrid(vm)
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .kerning(-1)
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }

    // MARK: - Digest card

    @ViewBuilder
    private func digestCard(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SparkleAccent(size: 20)
                Text("Today's briefing")
                    .font(.headline)
                Spacer()
                if vm.isGeneratingDigest {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh briefing")
                }
            }

            if vm.isGeneratingDigest && vm.digest.isEmpty {
                Text("Thinking…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if let err = vm.errorMessage {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if vm.digest.isEmpty {
                Text("Pull down or tap refresh to generate your briefing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(vm.digest)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(AIGlowBorder(active: vm.isGeneratingDigest, cornerRadius: 24))
    }

    // MARK: - Nudges

    @ViewBuilder
    private func nudgesCard(_ nudges: [ProactiveSignals.Nudge]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Needs attention")
                    .font(.headline)
                Spacer()
                Text("\(nudges.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
            ForEach(nudges) { nudge in
                VStack(alignment: .leading, spacing: 4) {
                    Text(nudge.title)
                        .font(.subheadline.weight(.semibold))
                    Text(nudge.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.orange.opacity(0.08))
        )
    }

    // MARK: - Quick actions

    @ViewBuilder
    private func quickActionsGrid(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick")
                .font(.headline)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickTile(icon: "bubble.left.and.bubble.right.fill", label: "Chat", tint: .blue, tab: .chat)
                quickTile(icon: "brain.filled.head.profile", label: "Memory", tint: .purple, tab: .memory)
                quickTile(icon: "books.vertical.fill", label: "Knowledge", tint: .green, tab: .knowledgeBase)
                quickTile(icon: "gear", label: "Settings", tint: .gray, tab: .settings)
            }
        }
    }

    private func quickTile(icon: String, label: String, tint: Color, tab: AppTab) -> some View {
        Button {
            // Jump to target tab — we use the shared AppRouter from Environment.
            NotificationCenter.default.post(name: .eidosJumpToTab, object: tab)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Background gradient

    private var timeGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: Date())
        let colors: [Color] = switch hour {
        case 5..<9:   [.orange.opacity(0.15), .yellow.opacity(0.08), .clear]   // dawn
        case 9..<17:  [.blue.opacity(0.10),   .cyan.opacity(0.05),   .clear]   // day
        case 17..<21: [.orange.opacity(0.20), .pink.opacity(0.10),   .clear]   // sunset
        default:      [.indigo.opacity(0.20), .purple.opacity(0.10), .clear]   // night
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

extension Notification.Name {
    static let eidosJumpToTab = Notification.Name("eidos.jumpToTab")
}
