import Foundation
import Darwin.Mach
#if canImport(UIKit)
import UIKit
#endif

/// Runtime classification of the device we're running on.
///
/// Three dimensions matter for LLM efficiency:
///   - **Form factor**: iPhone has tighter thermal envelope than iPad/Mac.
///     TPS degrades with context on iPhone; iPad/Mac mostly doesn't.
///   - **Current thermal state**: `ProcessInfo.ThermalState` — governs
///     how aggressively we shrink context / disable features.
///   - **Physical RAM**: >8 GB means we can afford long-context packing.
///
/// Eidos reads this once per prompt build to pick budgets and reasoning
/// mode. Cheap — no hardware probes, just ProcessInfo + UIDevice.
enum DeviceProfile {

    /// Categorical form factor. We don't distinguish between iPhone models
    /// — the thermal profile is similar across A17/A18/A19.
    enum FormFactor: Sendable {
        case iPhone          // iPhone — tighter thermals, shorter context
        case iPad            // iPad — generous thermals
        case mac             // Mac (Designed for iPad or Catalyst) — essentially unlimited
        case simulator       // any simulator — unlimited; we mock inference anyway
    }

    /// Backing cache for `formFactor`. Resolved once at app launch by
    /// `warmUp()` running on `@MainActor`, then read freely from any
    /// queue. Marked `nonisolated(unsafe)` because Swift 6's strict
    /// concurrency can't prove our single-write-during-bootstrap pattern,
    /// but it's safe in practice: bootstrap completes before any code
    /// reaches `formFactor` from a background actor.
    nonisolated(unsafe) private static var _formFactor: FormFactor = {
        // Default during the brief window before `warmUp()` runs. We pick
        // a value that matches our actual ship target (iPhone) so that any
        // accidental early read still produces a sane budget, not an iPad
        // budget that would over-tax the device.
        #if targetEnvironment(simulator)
        return .simulator
        #elseif targetEnvironment(macCatalyst)
        return .mac
        #elseif canImport(UIKit)
        if ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
        // CRITICAL: do NOT call `UIDevice.current` here. This static
        // initializer runs lazily on whichever queue first reads the
        // value, which is frequently a Swift cooperative pool thread
        // (e.g. from inside an actor's `generate()`). `UIDevice.current`
        // is `@MainActor` in Swift 6, and `MainActor.assumeIsolated` from
        // a non-main queue triggers `dispatch_assert_queue_fail` →
        // EXC_BREAKPOINT (SIGTRAP). We default to `.iPhone` and let
        // `warmUp()` upgrade to `.iPad` from MainActor at app launch.
        return .iPhone
        #else
        return .mac
        #endif
    }()

    /// Device form factor. Stable for the lifetime of the process.
    ///
    /// To distinguish iPad from iPhone, call `DeviceProfile.warmUp()`
    /// from `EidosApp.init()` (MainActor) at app launch — that captures
    /// `UIDevice.current.userInterfaceIdiom` on the main thread and
    /// caches it before any background actor reads `formFactor`.
    static var formFactor: FormFactor { _formFactor }

    /// Pre-resolves the form factor by reading `UIDevice.current` from
    /// MainActor. **Must** be called from `EidosApp.init()` or another
    /// guaranteed-MainActor entry point at the very top of bootstrap,
    /// before any actor or `Task.detached` reads `formFactor`.
    ///
    /// Idempotent and cheap. Safe to call multiple times.
    @MainActor
    static func warmUp() {
        #if targetEnvironment(simulator)
        _formFactor = .simulator
        #elseif targetEnvironment(macCatalyst)
        _formFactor = .mac
        #elseif canImport(UIKit)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            _formFactor = .mac
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            _formFactor = .iPad
        } else {
            _formFactor = .iPhone
        }
        #else
        _formFactor = .mac
        #endif
    }

    /// Physical memory in GB. Used to gate long-context packing.
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824  // 1024^3
    }

    /// Current thermal state. Call at the top of each `build(...)` —
    /// cheap, always current.
    static var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    /// True when the device is thermally strained. Eidos should pick
    /// shorter context, prefer `.fast` reasoning, and skip chain-of-thought.
    static var isThermallyStrained: Bool {
        switch thermalState {
        case .serious, .critical: true
        default: false
        }
    }

    /// Budget for retrieved context in characters. Tighter on iPhone
    /// because context length is the biggest TPS killer on iPhone
    /// specifically (not iPad, not Mac).
    ///
    /// Thermal escalation shrinks further — a hot iPhone with too much
    /// context throttles within 2-3 generations.
    static func contextBudgetChars(longContextFlag: Bool) -> Int {
        let base: Int
        switch formFactor {
        case .iPhone:
            base = longContextFlag ? 20_000 : 8_000
        case .iPad, .simulator:
            base = longContextFlag ? 60_000 : 12_000
        case .mac:
            // Macs have no meaningful context ceiling for E2B at 128 K window.
            base = longContextFlag ? 60_000 : 12_000
        }

        // Thermal degradation: halve context when strained.
        return isThermallyStrained ? base / 2 : base
    }

    /// Maximum tokens to generate. Shrinks on iPhone under thermal
    /// pressure to keep each turn short — bursty inference, back to idle.
    static var maxGenerationTokens: Int {
        if isThermallyStrained {
            return formFactor == .iPhone ? 256 : 512
        }
        switch formFactor {
        case .iPhone: return 768
        case .iPad, .simulator: return 1_024
        case .mac: return 1_536
        }
    }

    /// System-prompt addendum to inject when the device is strained.
    /// Makes Gemma produce shorter replies, easing thermal pressure.
    static var thermalSystemHint: String? {
        guard isThermallyStrained else { return nil }
        return """

        ## Thermal notice
        The user's device is currently warm. Keep this reply to one or two \
        short sentences. Skip elaboration. If the question is complex, offer \
        to expand later when the device has cooled.
        """
    }

    /// Estimated free memory available to this app in MB, sampled from
    /// `mach_task_basic_info`. iOS doesn't expose a hard budget — this
    /// is `physicalMemory - residentSize` so it counts the worst case
    /// where every byte we haven't allocated is still in use by the
    /// system. Treat as a loose lower-bound on what we can safely
    /// allocate without tripping jetsam.
    static var availableMemoryMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return Int.max }
        let resident = Int(info.resident_size)
        let total = Int(ProcessInfo.processInfo.physicalMemory)
        return max(0, total - resident) / (1024 * 1024)
    }

    /// True when the foreground app is approaching iOS's jetsam ceiling.
    /// We use 800 MB headroom as the trip wire — below that, iPhone
    /// foreground apps frequently get killed mid-allocation. Used by
    /// inference paths to abort proactively with a clean Swift error
    /// instead of being SIGKILL'd by the kernel.
    static var isMemoryConstrained: Bool {
        availableMemoryMB < 800
    }

    /// Maximum number of sequential tool calls the agent loop is allowed
    /// to chain in a single user turn.
    ///
    /// - iPhone: 2 (thermal-conscious — each tool call is another full
    ///   Gemma generation; stacking >2 risks a throttle event on sustained
    ///   workloads)
    /// - iPad: 4
    /// - Mac: 5 (no thermal ceiling in practice)
    ///
    /// Under thermal strain we halve the cap on every form factor.
    static var maxToolHops: Int {
        let base: Int = switch formFactor {
        case .iPhone: 2
        case .iPad, .simulator: 4
        case .mac: 5
        }
        return isThermallyStrained ? max(1, base / 2) : base
    }
}
