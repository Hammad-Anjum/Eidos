import XCTest
@testable import Eidos

/// Tests for the UserDefaults-backed configuration of `NotificationScheduler`.
/// The UNUserNotificationCenter side-effects are only safe in an app
/// target with notification permission, so they're verified on-device.
@MainActor
final class NotificationSchedulerTests: XCTestCase {

    private let keys = [
        "eidos.digest.hour",
        "eidos.digest.minute",
        "eidos.digest.enabled",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testDefaultHourIsSevenAM() {
        let scheduler = NotificationScheduler()
        XCTAssertEqual(scheduler.digestHour, 7)
        XCTAssertEqual(scheduler.digestMinute, 0)
    }

    func testDefaultDigestIsDisabled() {
        let scheduler = NotificationScheduler()
        XCTAssertFalse(scheduler.digestEnabled)
    }

    func testHourPersistsAcrossInstances() {
        let a = NotificationScheduler()
        a.digestHour = 9
        a.digestMinute = 30
        let b = NotificationScheduler()
        XCTAssertEqual(b.digestHour, 9)
        XCTAssertEqual(b.digestMinute, 30)
    }

    func testEnabledFlagPersists() {
        let a = NotificationScheduler()
        a.digestEnabled = true
        let b = NotificationScheduler()
        XCTAssertTrue(b.digestEnabled)
    }
}
