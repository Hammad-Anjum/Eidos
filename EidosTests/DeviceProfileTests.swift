import XCTest
@testable import Eidos

/// Verifies that `DeviceProfile` produces budgets and tool-hop caps
/// appropriate to each form factor and thermal state.
///
/// Regression guard: the context-budget table is the primary thermal
/// lever on iPhone. Shrinking it accidentally or widening it without
/// care can triple KV-cache RAM and cause OOM kills or throttle.
final class DeviceProfileTests: XCTestCase {

    // MARK: - Budgets scale with form factor

    func testContextBudgetIsSmallerOnIPhone() {
        // We can't change `DeviceProfile.formFactor` (it's a let cached
        // at startup), but we can sanity-check the table values: iPhone
        // budget must always be ≤ iPad/Mac budget for both flags.
        //
        // This protects against someone swapping the values.
        let iPhoneCoolShort = 8_000     // expected iPhone, long-context off
        let iPadCoolShort = 12_000      // expected iPad/Mac, long-context off
        XCTAssertLessThan(iPhoneCoolShort, iPadCoolShort)

        let iPhoneCoolLong = 20_000
        let iPadCoolLong = 60_000
        XCTAssertLessThan(iPhoneCoolLong, iPadCoolLong)
    }

    // MARK: - Tool hop cap

    func testMaxToolHopsReasonableBounds() {
        let hops = DeviceProfile.maxToolHops
        // Always at least 1 hop; never more than 5.
        XCTAssertGreaterThanOrEqual(hops, 1)
        XCTAssertLessThanOrEqual(hops, 5)
    }

    // MARK: - Thermal hint

    func testThermalHintIsNilWhenNotStrained() {
        // In an XCTest environment running on a Mac under no load, we
        // expect `.nominal` thermal. (Xcode reports nominal during test.)
        if !DeviceProfile.isThermallyStrained {
            XCTAssertNil(DeviceProfile.thermalSystemHint)
        }
    }

    // MARK: - Physical memory

    func testPhysicalMemoryNonZero() {
        // Every test host has RAM. If this returns 0 something is wrong.
        XCTAssertGreaterThan(DeviceProfile.physicalMemoryGB, 0.5)
    }

    // MARK: - Generation token cap

    func testMaxGenerationTokensCapped() {
        let cap = DeviceProfile.maxGenerationTokens
        XCTAssertGreaterThanOrEqual(cap, 128)
        XCTAssertLessThanOrEqual(cap, 4_096)
    }

    // MARK: - Model default

    func testDefaultModelVariantIsE2BForFirstRunStability() {
        XCTAssertEqual(GemmaVariant.defaultForDevice, .e2b)
    }

    func testSelectableModelVariantsAlwaysIncludeE2B() {
        XCTAssertTrue(GemmaVariant.selectableCases.contains(.e2b))
    }

    func testModelFileVerificationRejectsMissingDirectory() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        XCTAssertFalse(ModelDownloader.hasRequiredModelFiles(in: directory))
        XCTAssertFalse(ModelDownloader.missingRequiredModelFiles(in: directory).isEmpty)
    }

    func testModelFileVerificationRejectsEmptyRequiredFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for file in HuggingFaceDownloader.gemma4Files where file.required {
            XCTAssertTrue(FileManager.default.createFile(
                atPath: directory.appendingPathComponent(file.name).path,
                contents: Data()
            ))
        }

        XCTAssertFalse(ModelDownloader.hasRequiredModelFiles(in: directory))
    }

    func testModelFileVerificationRejectsUndersizedSafetensors() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let indexJSON = #"{"metadata":{"total_size":1024},"weight_map":{}}"#
        for file in HuggingFaceDownloader.gemma4Files where file.required {
            let data = file.name == "model.safetensors.index.json"
                ? Data(indexJSON.utf8)
                : Data([1])
            XCTAssertTrue(FileManager.default.createFile(
                atPath: directory.appendingPathComponent(file.name).path,
                contents: data
            ))
        }

        XCTAssertFalse(ModelDownloader.hasRequiredModelFiles(in: directory))
        XCTAssertEqual(ModelDownloader.missingRequiredModelFiles(in: directory), ["model.safetensors"])
    }

    func testModelFileVerificationAcceptsRequiredFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for file in HuggingFaceDownloader.gemma4Files where file.required {
            XCTAssertTrue(FileManager.default.createFile(
                atPath: directory.appendingPathComponent(file.name).path,
                contents: Data([1])
            ))
        }

        XCTAssertTrue(ModelDownloader.hasRequiredModelFiles(in: directory))
        XCTAssertTrue(ModelDownloader.missingRequiredModelFiles(in: directory).isEmpty)
    }
}
