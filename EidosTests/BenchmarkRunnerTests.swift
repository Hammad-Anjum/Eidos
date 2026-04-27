import XCTest
@testable import Eidos

@MainActor
final class BenchmarkRunnerTests: XCTestCase {

    private var gemma: GemmaSession!
    private var runner: BenchmarkRunner!

    override func setUp() async throws {
        try await super.setUp()
        gemma = GemmaSession()
        try await gemma.load(variant: .e2b)
        runner = BenchmarkRunner(gemma: gemma, variant: .e2b)
    }

    func testSafetyPromptIsCaughtBeforeGeneration() async {
        let summary = await runner.run(subset: [.refusal], reasoning: .fast)
        let selfHarm = summary.results.first { $0.promptID == "refuse.selfharm" }

        XCTAssertEqual(selfHarm?.safetyGateCaught, true)
        XCTAssertEqual(selfHarm?.metrics.tokens, 0)
        XCTAssertEqual(selfHarm?.metrics.hadAudio, false)
    }

    func testVisionPromptRunsWhenVisionIsEnabled() async {
        let summary = await runner.run(
            subset: [.visionOCR],
            visionAvailable: true,
            audioAvailable: false,
            reasoning: .fast
        )

        XCTAssertEqual(summary.totalPrompts, 1)
        XCTAssertEqual(summary.results.first?.promptID, "vision.ocr.basic")
        XCTAssertEqual(summary.results.first?.metrics.hadImage, true)
    }

    func testAudioPromptSkipsWhenAudioUnavailable() async {
        let summary = await runner.run(
            subset: [.audioTranscription],
            visionAvailable: false,
            audioAvailable: false,
            reasoning: .fast
        )

        XCTAssertEqual(summary.totalPrompts, 0)
        XCTAssertTrue(summary.results.isEmpty)
    }

    func testReasoningModeIsRecordedPerResult() async {
        let summary = await runner.run(
            subset: [.shortChat],
            visionAvailable: false,
            audioAvailable: false,
            reasoning: .reasoning
        )

        XCTAssertFalse(summary.results.isEmpty)
        XCTAssertTrue(summary.results.allSatisfy { $0.reasoningMode == ReasoningMode.reasoning.rawValue })
        XCTAssertTrue(summary.results.allSatisfy { $0.metrics.reasoningMode })
    }
}
