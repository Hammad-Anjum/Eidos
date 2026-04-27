import XCTest
@testable import Eidos

final class EidosLoggerTests: XCTestCase {

    func testEntryEncodesAndDecodes() throws {
        let entry = EidosLogEntry(
            timestamp: "2026-04-23T10:30:00.000Z",
            level: .info,
            category: .model,
            event: "test.event",
            message: "hi",
            payload: [
                "count": .int(42),
                "ratio": .double(0.5),
                "flag": .bool(true),
                "nested": .dict(["a": .string("b")]),
            ],
            failure: .modelLoad
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(EidosLogEntry.self, from: data)
        XCTAssertEqual(decoded.event, "test.event")
        XCTAssertEqual(decoded.category, .model)
        XCTAssertEqual(decoded.level, .info)
        XCTAssertEqual(decoded.failure, .modelLoad)
    }

    func testAnyCodableValueRoundTripsAllTypes() throws {
        let samples: [AnyCodableValue] = [
            .null,
            .bool(true),
            .int(7),
            .double(3.14),
            .string("hello"),
            .array([.int(1), .int(2), .int(3)]),
            .dict(["k": .string("v")]),
        ]
        let data = try JSONEncoder().encode(samples)
        let decoded = try JSONDecoder().decode([AnyCodableValue].self, from: data)
        XCTAssertEqual(decoded.count, samples.count)
    }

    func testFailureCategoryLabelsAreStable() {
        // Protects against accidental rename — the labels are
        // user-visible in Diagnostics and in exported reports.
        XCTAssertEqual(FailureCategory.modelLoad.displayLabel, "Model load")
        XCTAssertEqual(FailureCategory.modelThermal.displayLabel, "Thermal throttle")
        XCTAssertEqual(FailureCategory.unknown.displayLabel, "Unknown")
    }

    func testLogLevelOrderingIsCorrect() {
        XCTAssertTrue(EidosLogLevel.debug < EidosLogLevel.info)
        XCTAssertTrue(EidosLogLevel.info < EidosLogLevel.warn)
        XCTAssertTrue(EidosLogLevel.warn < EidosLogLevel.error)
        XCTAssertTrue(EidosLogLevel.error < EidosLogLevel.metric)
    }
}
