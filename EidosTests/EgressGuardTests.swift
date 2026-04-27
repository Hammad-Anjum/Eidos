import XCTest
@testable import Eidos

final class EgressGuardTests: XCTestCase {

    override func tearDown() {
        EgressGuard.isModelDownloadInProgress = false
        super.tearDown()
    }

    // MARK: - Host allowlist

    func testAllowsHuggingFaceCoExact() {
        XCTAssertTrue(EgressGuard.isAllowed(host: "huggingface.co"))
    }

    func testAllowsHuggingFaceCoSubdomains() {
        XCTAssertTrue(EgressGuard.isAllowed(host: "cdn-lfs.huggingface.co"))
        XCTAssertTrue(EgressGuard.isAllowed(host: "cdn-lfs-us-1.huggingface.co"))
        XCTAssertTrue(EgressGuard.isAllowed(host: "cdn-lfs-eu-1.huggingface.co"))
    }

    func testAllowsHfCoShortDomain() {
        XCTAssertTrue(EgressGuard.isAllowed(host: "hf.co"))
        XCTAssertTrue(EgressGuard.isAllowed(host: "cdn-lfs.hf.co"))
    }

    func testRejectsLookalikeDomains() {
        XCTAssertFalse(EgressGuard.isAllowed(host: "huggingface.co.evil.com"))
        XCTAssertFalse(EgressGuard.isAllowed(host: "fakehuggingface.co"))
        XCTAssertFalse(EgressGuard.isAllowed(host: "hf.co.attacker.net"))
    }

    func testRejectsUnrelatedHosts() {
        XCTAssertFalse(EgressGuard.isAllowed(host: "example.com"))
        XCTAssertFalse(EgressGuard.isAllowed(host: "api.openai.com"))
        XCTAssertFalse(EgressGuard.isAllowed(host: "apple.com"))
    }

    // MARK: - URLProtocol gate

    /// With the guard armed and download NOT in progress, every request is
    /// intercepted (`canInit` returns true).
    func testInterceptsAllWhenNotDownloading() {
        EgressGuard.isModelDownloadInProgress = false
        let requests = [
            URLRequest(url: URL(string: "https://huggingface.co/anything")!),
            URLRequest(url: URL(string: "https://apple.com/")!),
            URLRequest(url: URL(string: "https://example.com/foo")!),
        ]
        for request in requests {
            XCTAssertTrue(
                EgressGuardProtocol.canInit(with: request),
                "Expected to intercept \(request.url?.host ?? "?") while idle"
            )
        }
    }

    /// With download active, allowed hosts pass through untouched.
    func testAllowsWhitelistedHostsDuringDownload() {
        EgressGuard.isModelDownloadInProgress = true
        let request = URLRequest(url: URL(string: "https://cdn-lfs-us-1.huggingface.co/repos/foo/bar")!)
        XCTAssertFalse(
            EgressGuardProtocol.canInit(with: request),
            "Expected HuggingFace CDN to pass through during download"
        )
    }

    /// With download active, non-allowed hosts are still intercepted.
    func testStillBlocksOthersDuringDownload() {
        EgressGuard.isModelDownloadInProgress = true
        let request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        XCTAssertTrue(
            EgressGuardProtocol.canInit(with: request),
            "Expected OpenAI host to be intercepted even during download"
        )
    }

    func testRequestWithoutHostIsIntercepted() {
        let request = URLRequest(url: URL(string: "file:///tmp/foo")!)
        XCTAssertTrue(EgressGuardProtocol.canInit(with: request))
    }
}
