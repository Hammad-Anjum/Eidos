import SwiftUI
import SwiftData
import MLX

@main
struct EidosApp: App {

    @State private var container: AppContainer?
    @State private var initError: String?
    /// Drives the FaceID / passcode lock. Owned at app level so it
    /// survives container re-creates.
    @State private var lock = AppLockController()

    init() {
        // Pre-resolve `DeviceProfile.formFactor` on the main thread BEFORE
        // any background actor reads it. The static-let lazy initializer
        // would otherwise fire on whichever cooperative pool thread first
        // hits `DeviceProfile.maxGenerationTokens`, which trips a
        // MainActor isolation assertion → EXC_BREAKPOINT. See the
        // comment on `DeviceProfile._formFactor`.
        DeviceProfile.warmUp()

        // Catch every uncaught NSException + Swift signal we can. iOS
        // doesn't surface a `.ips` for sideloaded free-team apps and
        // jetsam kills don't go through this path either, but for the
        // CASES we CAN catch — Objective-C exceptions, BAD_ACCESS in
        // pure Swift code, etc. — we at least write a final breadcrumb
        // so the next launch's log tail tells us what died. Without
        // this, any of those terminations look identical to a kernel
        // SIGKILL: no log line, no `.ips`, just an app restart.
        Self.installCrashBreadcrumbs()

        // Observe iOS memory-pressure warnings. When the system signals
        // pressure, we proactively call `MLX.Memory.clearCache()` so a
        // following inference call has the maximum possible headroom
        // and we don't pile our cached buffers on top of an already
        // strained system. Cheap + entirely local.
        Self.installMemoryPressureObserver()

        // Bootstrap the biometric lock state. If `appLockEnabled` is
        // on AND the device supports auth, this sets `isLocked = true`
        // so the lock view covers the UI from the very first frame.
        let initialLock = AppLockController()
        initialLock.bootstrapLockState()
        _lock = State(initialValue: initialLock)

        do {
            _container = State(initialValue: try AppContainer())
        } catch {
            _initError = State(initialValue: error.localizedDescription)
        }
    }

    // MARK: - Stability hooks

    /// Logs a final breadcrumb on any catchable abnormal termination
    /// path. iOS sandbox + free-team signing means `.ips` files often
    /// don't get written; the JSONL we control does.
    private static func installCrashBreadcrumbs() {
        NSSetUncaughtExceptionHandler { exception in
            EidosLogger.shared.log(
                .error, category: .app,
                event: "app.uncaught-exception",
                message: "\(exception.name.rawValue): \(exception.reason ?? "(no reason)")",
                payload: [
                    "stack": exception.callStackSymbols.joined(separator: " | "),
                ],
                failure: .crashHandler
            )
            // Force a synchronous flush before the process dies.
            EidosLogger.shared.flushSynchronously()
        }

        // Common fatal signals iOS will deliver to our process.
        // Setting these up gives us one last log line before exit.
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE] {
            signal(sig) { signalNumber in
                EidosLogger.shared.log(
                    .error, category: .app,
                    event: "app.fatal-signal",
                    payload: ["signal": Int(signalNumber)],
                    failure: .crashHandler
                )
                EidosLogger.shared.flushSynchronously()
                // Restore default handler and re-raise so the system
                // can do its normal post-mortem dance.
                signal(signalNumber, SIG_DFL)
                raise(signalNumber)
            }
        }
    }

    /// Subscribes to `UIApplication.didReceiveMemoryWarningNotification`
    /// (iOS) and frees MLX caches eagerly when iOS hints we're close to
    /// the foreground budget. This is preventative — it doesn't catch
    /// all jetsam kills, but for any pressure that DOES surface as a
    /// warning we get to drop ~hundreds of MB before the kernel acts.
    private static func installMemoryPressureObserver() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            EidosLogger.shared.log(.warn, category: .app,
                event: "app.memory-warning",
                payload: ["available_mb": DeviceProfile.availableMemoryMB])
            // Don't acquire the inference lock — just hit MLX's cache
            // synchronously. Worst case the next inference's prefill
            // re-warms a few MB.
            #if !targetEnvironment(simulator)
            MLX.Memory.clearCache()
            #endif
        }
        #endif
    }

    @State private var showFeatureTour = false
    /// Tracks app foreground/background. We blur the UI when the app
    /// resigns active so iOS's app-switcher snapshot doesn't capture
    /// chat / memory content. Privacy-product table stakes.
    @Environment(\.scenePhase) private var scenePhase
    @State private var isObscured: Bool = false

    var body: some Scene {
        WindowGroup {
            if let container {
                Group {
                    let phase = container.modelDownloader.phase
                    if container.isBootstrapped && phase == .ready {
                        RootView()
                    } else if container.isBootstrapped && phase.errorMessage != nil {
                        ModelDownloadView(variant: container.modelDownloader.selectedVariant)
                    } else if container.isBootstrapped {
                        OnboardingView()
                    } else {
                        StartupModelStatusView()
                    }
                }
                // Privacy overlay: when scenePhase resigns active (going
                // to background, app switcher, or split-view drag), the
                // entire UI is covered so the snapshot iOS records for
                // the app switcher cannot show sensitive memory / chat
                // content. Restored when the app returns to .active.
                .overlay {
                    if isObscured {
                        PrivacySnapshotOverlay()
                            .transition(.opacity)
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // .active is the only state where chat / memory is
                    // actually being looked at by the user. .inactive
                    // and .background both happen mid-snapshot, so we
                    // hide content for both.
                    isObscured = (newPhase != .active)
                    // Foreground crossing: re-evaluate whether the lock
                    // should re-engage (>5 min backgrounded).
                    if oldPhase != .active && newPhase == .active {
                        lock.handleForegroundTransition()
                    }
                    // Background crossing: hook for any future
                    // background work AppLockController might want.
                    if oldPhase == .active && newPhase != .active {
                        lock.handleBackgroundTransition()
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { lock.isLocked },
                    set: { _ in /* AppLockController owns this */ }
                )) {
                    AppLockView()
                        .environment(lock)
                }
                .environment(lock)
                .environment(container)
                .modelContainer(container.modelContainer)
                .task { await container.bootstrap() }
                .onChange(of: container.modelDownloader.phase) { _, phase in
                    if phase == .ready && !UserDefaults.standard.bool(forKey: FeatureTourView.seenKey) {
                        showFeatureTour = true
                    }
                }
                .sheet(isPresented: $showFeatureTour) {
                    FeatureTourView()
                        .interactiveDismissDisabled(false)
                }
                .onOpenURL { url in
                    // `eidos://chat`, `eidos://home`, etc. — used by the
                    // widget's control intents and App Intents.
                    guard url.scheme == "eidos" else { return }
                    let tab: AppTab = switch url.host {
                    case "chat": .chat
                    case "home": .home
                    case "memory": .memory
                    case "knowledge": .knowledgeBase
                    case "settings": .settings
                    default: .home
                    }
                    NotificationCenter.default.post(name: .eidosJumpToTab, object: tab)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Eidos failed to start.")
                        .font(.headline)
                    if let initError {
                        Text(initError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}

private struct StartupModelStatusView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let downloader = container.modelDownloader
        VStack(spacing: 16) {
            Spacer()

            switch downloader.phase {
            case .downloading:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Downloading Gemma")
                    .font(.title3.bold())
                ProgressView(value: downloader.progress)
                    .padding(.horizontal, 48)
                Text("\(Int(downloader.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .loading:
                Image(systemName: "cpu")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Loading Gemma on this iPhone")
                    .font(.title3.bold())
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 48)
                Text("Downloaded files found. Eidos will open chat after MLX finishes preparing the model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Model setup failed")
                    .font(.title3.bold())
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

            case .idle, .ready:
                ProgressView("Starting Eidos...")
                    .controlSize(.large)
            }

            Spacer()
        }
        .padding()
    }
}
