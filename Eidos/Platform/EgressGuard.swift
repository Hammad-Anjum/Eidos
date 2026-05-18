import Foundation

// Auditable no-egress guarantee. All outbound traffic is blocked unless a
// model download is in progress AND the host is allowed. Armed after
// bootstrap() completes.
//
// ## Coverage limitation — background URLSessions
//
// `URLProtocol` interception applies ONLY to foreground (`.default` /
// `.ephemeral`) URLSession configurations. Background-configured
// sessions (`URLSessionConfiguration.background(withIdentifier:)`)
// run inside `nsurlsessiond`, OUT of our process, and bypass our
// URLProtocol entirely. The privacy guarantee silently degrades in
// that case.
//
// At time of writing (2026-05-13) no background URLSession exists in
// this codebase — `SecureHTTPSSession` and `ModelDownloader` both use
// foreground configs. If a future feature adds a background session,
// the egress filter MUST be reimplemented at the
// `URLSessionTaskDelegate` layer (intercepting `urlSession(_:task:
// willPerformHTTPRedirection:newRequest:completionHandler:)` and the
// initial task creation). Filing this footgun explicitly here so the
// next engineer who reaches for `URLSessionConfiguration.background`
// has to read the warning first.
enum EgressGuard {
    // Allowed during model download. Matched by suffix so all HuggingFace
    // CDN regions (cdn-lfs-us-1, cdn-lfs-eu-1, cdn-lfs.hf.co, …) pass.
    static let allowedSuffixes: [String] = [
        "huggingface.co",
        "hf.co",
    ]

    nonisolated(unsafe) static var isModelDownloadInProgress = false

    /// Wall-clock time the URLProtocol was armed. `nil` until
    /// `install()` runs (i.e. until `AppContainer.bootstrap()`
    /// reaches its egress-arm point). Surfaced by the Memory tab's
    /// privacy ribbon so the user sees a concrete "locked down since
    /// HH:MM" timestamp instead of a vague claim.
    nonisolated(unsafe) static var installedAt: Date?

    static func install() {
        URLProtocol.registerClass(EgressGuardProtocol.self)
        if installedAt == nil { installedAt = Date() }
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
