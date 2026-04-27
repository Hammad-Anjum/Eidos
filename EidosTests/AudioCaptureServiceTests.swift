import XCTest
@testable import Eidos

@MainActor
final class AudioCaptureServiceTests: XCTestCase {

    func testSimulatorCaptureProducesInMemoryPCM() async throws {
        let service = AudioCaptureService()

        try await service.requestPermission()
        try service.start()

        XCTAssertTrue(service.isRecording)
        let buffer = try await service.stopAndReturnBuffer()

        XCTAssertFalse(service.isRecording)
        XCTAssertGreaterThan(buffer.count, 0)
        XCTAssertGreaterThan(service.capturedSeconds, 0)
    }

    func testCancelClearsPendingBuffer() async throws {
        let service = AudioCaptureService()

        try service.start()
        service.cancel()

        XCTAssertFalse(service.isRecording)
        let buffer = try await service.stopAndReturnBuffer()
        XCTAssertTrue(buffer.isEmpty)
    }

    func testSecondCaptureStartsFresh() async throws {
        let service = AudioCaptureService()

        try service.start()
        let first = try await service.stopAndReturnBuffer()

        try service.start()
        let second = try await service.stopAndReturnBuffer()

        XCTAssertEqual(first.count, second.count)
        XCTAssertGreaterThan(second.count, 0)
    }
}
