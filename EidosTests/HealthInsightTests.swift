import XCTest
@testable import Eidos

/// HealthKit itself requires device permission so it's exercised on-device.
/// These tests pin down the pure rendering logic of `HealthInsight`.
final class HealthInsightTests: XCTestCase {

    func testEmptyInsightRendersPlaceholder() {
        let i = HealthInsight()
        XCTAssertEqual(i.readableLine, "No health data available.")
    }

    func testRenderingIncludesAllSetFields() {
        var i = HealthInsight()
        i.stepsYesterday = 12345
        i.sleepHoursLastNight = 7.2
        i.activeEnergyYesterdayKcal = 420
        i.restingHeartRate = 58
        let s = i.readableLine
        XCTAssertTrue(s.contains("7.2"))
        XCTAssertTrue(s.contains("12,345") || s.contains("12345"))
        XCTAssertTrue(s.contains("420"))
        XCTAssertTrue(s.contains("58"))
    }

    func testPartialRendering() {
        var i = HealthInsight()
        i.sleepHoursLastNight = 8.0
        let s = i.readableLine
        XCTAssertTrue(s.contains("8.0"))
        XCTAssertFalse(s.contains("steps"))
    }
}
