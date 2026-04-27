import XCTest
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
@testable import Eidos

final class GemmaSessionMultimodalTests: XCTestCase {

    func testSimulatorMockAcceptsImageInput() async throws {
        let gemma = GemmaSession()
        try await gemma.load(variant: .e2b)

        let stream = try await gemma.generate(
            messages: [["role": "user", "content": "Describe this image."]],
            images: [makeTestImage()]
        )

        var response = ""
        for try await chunk in stream {
            response += chunk
        }

        XCTAssertFalse(response.isEmpty)
    }

    func testAudioParameterDoesNotCrashWhenUnsupported() async throws {
        let gemma = GemmaSession()
        try await gemma.load(variant: .e2b)

        let stream = try await gemma.generate(
            messages: [["role": "user", "content": "Please help with this audio."]],
            audio: Data([0, 1, 2, 3])
        )

        var response = ""
        for try await chunk in stream {
            response += chunk
        }

        XCTAssertFalse(response.isEmpty)
        XCTAssertFalse(GemmaSession.supportsNativeAudioInput)
    }

    private func makeTestImage() -> CGImage {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            UIColor.systemBlue.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 24, y: 24, width: 80, height: 80))
        }
        return image.cgImage!
        #else
        XCTFail("UIKit image renderer unavailable in this test target")
        fatalError("Unreachable")
        #endif
    }
}
