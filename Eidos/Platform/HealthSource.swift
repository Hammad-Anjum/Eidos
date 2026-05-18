import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// A compact health snapshot for the last 24 hours / previous night.
struct HealthInsight: Sendable, Equatable {
    var stepsYesterday: Int?
    var sleepHoursLastNight: Double?
    var restingHeartRate: Double?
    var activeEnergyYesterdayKcal: Double?

    /// One-line summary for prompt injection / digest rendering.
    var readableLine: String {
        var parts: [String] = []
        if let s = sleepHoursLastNight {
            parts.append(String(format: "slept %.1f h", s))
        }
        if let steps = stepsYesterday {
            parts.append("\(steps.formatted()) steps yesterday")
        }
        if let kcal = activeEnergyYesterdayKcal {
            parts.append("\(Int(kcal)) kcal active")
        }
        if let hr = restingHeartRate {
            parts.append(String(format: "resting HR %.0f", hr))
        }
        return parts.isEmpty ? "No health data available." : parts.joined(separator: ", ")
    }
}

/// Reads a minimal set of HealthKit metrics. Insights only — we never
/// store raw samples, and nothing ever leaves the device.
///
/// Permissions are requested once; denial yields empty insights rather
/// than errors so the digest still renders cleanly.
actor HealthSource {

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif
    private(set) var hasPermission = false

    init() {}

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            hasPermission = false
            return false
        }
        let types: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            // iOS doesn't tell us whether the user granted anything — we
            // discover that at query time. Mark permission as "attempted".
            hasPermission = true
            return true
        } catch {
            hasPermission = false
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Snapshot

    func latestInsight() async -> HealthInsight {
        #if canImport(HealthKit)
        guard hasPermission else { return HealthInsight() }
        async let steps = stepsYesterday()
        async let sleep = sleepHoursLastNight()
        async let rhr = mostRecentRestingHeartRate()
        async let kcal = activeEnergyYesterday()
        return await HealthInsight(
            stepsYesterday: steps,
            sleepHoursLastNight: sleep,
            restingHeartRate: rhr,
            activeEnergyYesterdayKcal: kcal
        )
        #else
        return HealthInsight()
        #endif
    }

    // MARK: - Queries

    #if canImport(HealthKit)

    private func stepsYesterday() async -> Int? {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let (start, end) = Self.yesterdayRange()
        return await sumQuantity(type: type, unit: .count(), start: start, end: end)
            .map(Int.init)
    }

    private func activeEnergyYesterday() async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let (start, end) = Self.yesterdayRange()
        return await sumQuantity(type: type, unit: .kilocalorie(), start: start, end: end)
    }

    private func mostRecentRestingHeartRate() async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        return await latestSample(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    private func sleepHoursLastNight() async -> Double? {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let (start, end) = Self.lastNightRange()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil); return
                }
                // Count only the `.asleep*` categories.
                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let totalSeconds = samples
                    .filter { asleep.contains($0.value) }
                    .map { $0.endDate.timeIntervalSince($0.startDate) }
                    .reduce(0, +)
                cont.resume(returning: totalSeconds > 0 ? totalSeconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    // MARK: - HK helpers

    private func sumQuantity(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date, end: Date
    ) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestSample(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                let sample = (samples?.first as? HKQuantitySample)
                cont.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    #endif

    // MARK: - Date ranges

    private static func yesterdayRange() -> (Date, Date) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        return (startOfYesterday, startOfToday)
    }

    private static func lastNightRange() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        // Sleep window: 6pm yesterday → noon today (captures late-night + late wake).
        let startOfToday = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .hour, value: -6, to: cal.date(byAdding: .day, value: -1, to: startOfToday)!)!
        let end = cal.date(byAdding: .hour, value: 12, to: startOfToday)!
        return (start, end)
    }
}
