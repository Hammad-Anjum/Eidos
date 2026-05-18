import SwiftUI

/// Home for Eidos AuADHD companion.
///
/// Four voice-first / camera-first tiles, an energy slider à la Spoons,
/// and a softly-changing time-of-day gradient. The whole view is
/// shaped for AuDHD execution-function load:
///   - Tiles are minimum 130pt tall (well over Apple's 44pt
///     accessibility minimum) so motor-tremor users hit them cleanly.
///   - Every interactive element has `accessibilityLabel` +
///     `accessibilityHint` so VoiceOver users navigate eyes-closed.
///   - The energy slider is the only persisted setting on this view
///     (`@AppStorage`). All other state is derived per render.
///   - Tile taps fire IMMEDIATELY — no confirmation steps, no
///     "are you sure", no review screens. The user taps because
///     they need help now.
///
/// Tile dispatch goes through `AppContainer.pendingChatLaunch`:
/// HomeView writes a `ChatLaunchIntent`, posts `.eidosJumpToTab` →
/// `.chat`, and `ChatView` drains the intent on its next render to
/// fire `ChatViewModel.send(...)`. The Journal tile is the one
/// exception — it presents a full-screen recording view that calls
/// `VoiceJournalCaptureSkill` directly (bypassing Gemma).
struct HomeView: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = HomeViewModel()

    /// Energy level 0-4. Persisted across launches via `@AppStorage`.
    /// Injected into the What Now tile's prompt so `pick_next_task`
    /// can pick a task sized to the user's current capacity.
    @AppStorage("eidos.auadhd.energyLevel") private var energyLevel: Int = 2

    /// Camera sheet for the Look tile.
    @State private var showCamera = false
    /// Full-screen journal recording view for the Journal tile.
    @State private var showJournal = false
    /// Full-screen body-doubling presence view for the "Sit With Me" tile.
    @State private var showBodyDoubling = false
    /// Crisis-resources sheet for the "I need help now" bar.
    @State private var showCrisis = false

    /// Captured at the start of a slider drag so we can log a memory
    /// entry only when the value actually *changes* by the time the
    /// user lifts off. Without this, every step in a 0→4 drag would
    /// fire a write.
    @State private var energyBeforeDrag: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                timeGradient.ignoresSafeArea()
                ScrollView {
                    content
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView(
                onCaptured: { cg in
                    showCamera = false
                    fireLookIntent(with: cg)
                },
                onCancelled: { showCamera = false }
            )
        }
        .fullScreenCover(isPresented: $showJournal) {
            JournalRecordingView { _ in
                showJournal = false
            }
        }
        .fullScreenCover(isPresented: $showBodyDoubling) {
            BodyDoublingView { showBodyDoubling = false }
        }
        .sheet(isPresented: $showCrisis) {
            CrisisResourcesView()
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            crisisChip
            header
            TodayAgendaLine()
            sitWithMeHero
            energySection
            tilesGrid
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.greeting)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .kerning(-1)
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.greeting). \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))")
    }

    // MARK: - Energy slider

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Decorative header row for sighted users. Hidden from
            // VoiceOver — the Slider below carries the same info via
            // its accessibilityLabel + accessibilityValue, and
            // surfacing it twice fragments VoiceOver focus on the
            // eyes-closed pass.
            HStack(alignment: .firstTextBaseline) {
                Text("Energy")
                    .font(.headline)
                Spacer()
                Text(Self.energyLabel(for: energyLevel))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { Double(energyLevel) },
                    set: { energyLevel = Int($0.rounded()) }
                ),
                in: 0...4,
                step: 1,
                onEditingChanged: { isEditing in
                    if isEditing {
                        energyBeforeDrag = energyLevel
                    } else {
                        logEnergyChange(from: energyBeforeDrag, to: energyLevel)
                    }
                }
            )
            .tint(.purple)
            .accessibilityLabel("Energy level, zero is burnout, four is high.")
            .accessibilityValue("\(energyLevel) of 4 — \(Self.energyLabel(for: energyLevel))")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Tiles grid

    /// Opacity applied to the 2×2 secondary tile grid based on current
    /// energy. At burnout / low energy the grid quietly recedes so the
    /// Sit With Me hero reads as the suggested action without us
    /// *hiding* anything (hiding affordances is a trust break — the
    /// AuDHD design rules forbid it). The energy slider itself and the
    /// Sit With Me hero stay full saturation: the slider is the user's
    /// only way to raise energy back, and the hero is the gentlest
    /// action available, so both must remain legible at every level.
    private var secondaryTileOpacity: Double {
        switch energyLevel {
        case 0:    0.50
        case 1:    0.65
        default:   1.0
        }
    }

    private var tilesGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            AuADHDTile(
                icon: "eye.fill",
                label: "Look",
                hint: "Opens the camera. Take a photo of a cluttered scene; Eidos describes a one-step plan.",
                tint: .blue,
                action: { showCamera = true }
            )
            AuADHDTile(
                icon: "waveform.path.ecg",
                label: "Ground",
                hint: "Plays a grounding script for RSD or overwhelm — sensory cue, breath, one physical action.",
                tint: .pink,
                action: fireGroundIntent
            )
            AuADHDTile(
                icon: "mic.fill",
                label: "Journal",
                hint: "Opens a full-screen mic. Tap once to start, tap again to stop. Saved to your private memory.",
                tint: .purple,
                action: { showJournal = true }
            )
            AuADHDTile(
                icon: "questionmark.bubble.fill",
                label: "What Now",
                hint: "Picks one thing to do based on your energy and your priority list.",
                tint: .orange,
                action: fireWhatNowIntent
            )
        }
        .opacity(secondaryTileOpacity)
        .animation(.easeInOut(duration: 0.35), value: energyLevel)
    }

    // MARK: - Crisis chip (top of screen)

    /// Slim crisis chip pinned to the top of Home.
    ///
    /// Moved here from the bottom (2026-05-18) so emergency resources
    /// are always one tap away without scrolling. Kept slim (~44pt) and
    /// muted-red so it reads as "available, not alarming" — a
    /// fluorescent banner at the top of every render would tonally
    /// collide with the calm aesthetic the audience needs.
    ///
    /// Same destination as the old `crisisBar` it replaces:
    /// `CrisisResourcesView` (988 / 911 / Crisis Text / grounding).
    /// Bypasses chat and Gemma entirely.
    private var crisisChip: some View {
        Button {
            showCrisis = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.red.opacity(0.85), in: Circle())
                Text("I need help now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("·  988  ·  911  ·  text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.08))
                    .overlay(
                        Capsule().stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I need help now")
        .accessibilityHint("Shows emergency resources — Suicide and Crisis Lifeline, 911, Crisis Text Line, and a grounding option. Does not contact anyone unless you tap a specific row.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sit With Me hero (flagship feature, opening statement)

    /// Hero card for body doubling — the AuADHD-audience differentiator.
    ///
    /// Promoted from a bottom bar to a top-of-fold hero (2026-05-18) so
    /// the flagship feature is the first substantive thing the user
    /// sees — and the first thing the App Store / demo video
    /// screenshots will show. The 220pt minimum height pushes the
    /// secondary 2×2 tiles down but stays inside the no-scroll fold
    /// on iPhone 17 and up.
    ///
    /// Wires the same path as the old `sitWithMeBar`:
    /// `showBodyDoubling = true` → `BodyDoublingView` full-screen cover.
    private var sitWithMeHero: some View {
        Button {
            showBodyDoubling = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: "person.line.dotted.person.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sit With Me")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Quiet timer.  One halfway check-in.  No questions.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.callout.weight(.semibold))
                    Text("Start a 5, 10, 15, or 25-min session")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.15), in: Capsule())
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.45, green: 0.25, blue: 0.85),
                             Color(red: 0.30, green: 0.18, blue: 0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26)
            )
            .shadow(color: .purple.opacity(0.35), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sit with me")
        .accessibilityHint("Opens a quiet body-doubling session. Eidos sets a timer, checks in once at the halfway mark, and acknowledges the close. No coaching, no questions.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Tile actions

    private func fireLookIntent(with image: CGImage) {
        container.pendingChatLaunch = ChatLaunchIntent(
            prompt: "I'm looking at this and I don't know where to start.",
            displayText: "(photo of what I'm looking at)",
            image: image,
            autoSend: true
        )
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
    }

    private func fireGroundIntent() {
        container.pendingChatLaunch = ChatLaunchIntent(
            prompt: "I'm spiraling. Help me ground.",
            autoSend: true
        )
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
    }

    private func fireWhatNowIntent() {
        let prompt = "What now? My energy is \(energyLevel) out of 4."
        container.pendingChatLaunch = ChatLaunchIntent(
            prompt: prompt,
            autoSend: true
        )
        NotificationCenter.default.post(name: .eidosJumpToTab, object: AppTab.chat)
    }

    // MARK: - Energy logging

    /// Writes a `MemoryEntry` for an energy change. Priority P4 keeps
    /// the high-volume entries (5–20 per day on a chatty user) out of
    /// the chat-recall hot set; they'd crowd genuinely-load-bearing
    /// memories otherwise. Tagged `energy` for the Memory-tab Today
    /// section, and `energy-YYYY-MM-DD` so a future trend view can
    /// pull a single day's entries with one tag lookup.
    ///
    /// Skipped when from==to: `onEditingChanged: false` fires even when
    /// the user taps the slider thumb without moving it. Logging a
    /// "stayed at 2" entry would be noise.
    private func logEnergyChange(from previous: Int, to current: Int) {
        guard previous != current else { return }
        let previousLabel = Self.energyLabel(for: previous)
        let currentLabel  = Self.energyLabel(for: current)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeOfDay = formatter.string(from: Date())

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayTag = dayFormatter.string(from: Date())

        let entry = MemoryEntry(
            tier: .recentSession,
            title: "Energy → \(current) (\(currentLabel))",
            body: "Moved from \(previous) (\(previousLabel)) to \(current) (\(currentLabel)) at \(timeOfDay).",
            priority: .p4,
            tags: ["energy", "energy-\(dayTag)"]
        )

        // Capture the actor reference before the detached task so we
        // never reach back into the MainActor-isolated container from a
        // background context.
        let memoryManager = container.memoryManager
        Task.detached {
            _ = try? await memoryManager.save(entry)
        }
    }

    // MARK: - Helpers

    /// Maps energy `0...4` to a one-word label. Mirrors the Spoons
    /// vocabulary deliberately: this audience already speaks the
    /// language.
    static func energyLabel(for level: Int) -> String {
        switch max(0, min(4, level)) {
        case 0: return "burnout"
        case 1: return "low"
        case 2: return "okay"
        case 3: return "good"
        default: return "high"
        }
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

// MARK: - Tile component

/// Secondary tile used by the AuADHD Home grid.
///
/// 110pt minimum height — still 2.5× the Apple HIG 44pt minimum, which
/// preserves the AuDHD-audience motor-tremor + eyes-closed-VoiceOver
/// affordance, while leaving vertical space for the Sit With Me hero
/// card above. Tint backgrounds use the material foreground so dark
/// mode reads cleanly.
///
/// Was 130pt before the 2026-05-18 Home rearrangement that promoted
/// Sit With Me to a hero card; lowering to 110pt was the only way to
/// keep the entire 4-tile + crisis + hero + energy layout above the
/// fold on iPhone 17 without forcing a scroll for the secondary
/// surfaces.
private struct AuADHDTile: View {
    let icon: String
    let label: String
    let hint: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: tint.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }
}

extension Notification.Name {
    static let eidosJumpToTab = Notification.Name("eidos.jumpToTab")
}
