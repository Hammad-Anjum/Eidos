import Foundation

// Auditable no-egress guarantee. All outbound traffic is blocked unless a
// model download is in progress AND the host is allowed. Armed after
// bootstrap() completes.
enum EgressGuard {
    // Allowed during model download. Matched by suffix so all HuggingFace
    // CDN regions (cdn-lfs-us-1, cdn-lfs-eu-1, cdn-lfs.hf.co, …) pass.
    static let allowedSuffixes: [String] = [
        "huggingface.co",
        "hf.co",
    ]

    nonisolated(unsafe) static var isModelDownloadInProgress = false

    static func install() {
        URLProtocol.registerClass(EgressGuardProtocol.self)
    }

    static func isAllowed(host: String) -> Bool {
        allowedSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) })
    }
}

final class EgressGuardProtocol: URLProtocol, @unchecked Sendable {

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return true }
        if EgressGuard.isModelDownloadInProgress, EgressGuard.isAllowed(host: host) {
            return false  // pass through to default session handling
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        #if DEBUG
        let host = request.url?.host ?? "unknown"
        print("[EgressGuard] BLOCK \(host)\(request.url?.path ?? "")")
        #endif
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
