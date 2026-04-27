import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Activity the user was doing at a given time.
enum ActivityKind: String, Sendable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}

/// Compact motion snapshot for the digest / memory.
struct MotionInsight: Sendable, Equatable {
    var steps: Int?
    var activeMinutes: Int?
    var dominantActivity: ActivityKind

    /// Human-readable one-liner.
    var readable: String {
        var parts: [String] = []
        if let steps { parts.append("\(steps.formatted()) steps") }
        if let activeMinutes, activeMinutes > 0 { parts.append("\(activeMinutes) active min") }
        if dominantActivity != .unknown && dominantActivity != .stationary {
            parts.append("mostly \(dominantActivity.rawValue)")
        }
        return parts.isEmpty ? "Movement data unavailable." : parts.joined(separator: ", ")
    }
}

/// Wraps CoreMotion's step counter + activity classifier. Everything
/// stays on-device — CoreMotion data is never transmitted by Apple.
///
/// CoreMotion is free (no permission on iPhones) for step count but
/// `CMMotionActivityManager` requires `NSMotionUsageDescription`.
actor MotionSource {

    #if canImport(CoreMotion)
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    #endif
    private(set) var hasPermission = false

    init() {}

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        #if canImport(CoreMotion)
        guard CMMotionActivityManager.isActivityAvailable() else {
            hasPermission = false
            return false
        }
        // Request by firing a dummy activity query — iOS surfaces the
        // permission prompt on first call.
        let status = CMMotionActivityManager.authorizationStatus()
        if status == .notDetermined {
            _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                activityManager.startActivityUpdates(to: .main) { _ in
                    self.activityManager.stopActivityUpdates()
                    cont.resume(returning: true)
                }
                // Make sure we don't hang forever if the system is slow.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    cont.resume(returning: true)
                }
            }
        }
        hasPermission = CMMotionActivityManager.authorizationStatus() == .authorized
        return hasPermission
        #else
        return false
        #endif
    }

    // MARK: - Queries

    /// Snapshot for yesterday — used by ProactiveDigestGenerator.
    func insightForYesterday() async -> MotionInsight {
        let (start, end) = Self.yesterdayRange()
        return await insight(from: start, to: end)
    }

    /// Snapshot for an arbitrary range.
    func insight(from start: Date, to end: Date) async -> MotionInsight {
        #if canImport(CoreMotion)
        async let steps = stepCount(from: start, to: end)
        async let activityMins = activeMinuteCount(from: start, to: end)
        async let dominant = dominantActivity(from: start, to: end)
        return await MotionInsight(
            steps: steps,
            activeMinutes: activityMins,
            dominantActivity: dominant
        )
        #else
        return MotionInsight(steps: nil, activeMinutes: nil, dominantActivity: .unknown)
        #endif
    }

    // MARK: - Internals

    #if canImport(CoreMotion)

    private func stepCount(from start: Date, to end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    private func activeMinuteCount(from start: Date, to end: Date) async -> Int? {
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }
        return await withCheckedContinuation { cont in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                guard let activities else { cont.resume(returning: nil); return }
                var secs: TimeInterval = 0
                for i in 0..<activities.count - 1 {
                    let a = activities[i]
                    let next = activities[i + 1]
                    if a.walking || a.running || a.cycling {
                        secs += next.startDate.timeIntervalSince(a.startDate)
                    }
                }
                cont.resume(returning: Int(secs / 60))
            }
        }
    }

    private func dominantActivity(from start: Date, to end: Date) async -> ActivityKind {
        guard CMMotionActivityManager.isActivityAvailable() else { return .unknown }
        return await withCheckedContinuation { cont in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                guard let activities, !activities.isEmpty else {
                    cont.resume(returning: .unknown); return
                }
                // Count occurrences; return the mode.
                var tally: [ActivityKind: Int] = [:]
                for a in activities {
                    let k = Self.classify(a)
                    tally[k, default: 0] += 1
                }
                let dominant = tally.max(by: { $0.value < $1.value })?.key ?? .unknown
                cont.resume(returning: dominant)
            }
        }
    }

    nonisolated private static func classify(_ a: CMMotionActivity) -> ActivityKind {
        if a.automotive { return .automotive }
        if a.cycling { return .cycling }
        if a.running { return .running }
        if a.walking { return .walking }
        if a.stationary { return .stationary }
        return .unknown
    }

    #endif

    private static func yesterdayRange() -> (Date, Date) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        return (startOfYesterday, startOfToday)
    }
}
