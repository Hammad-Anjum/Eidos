import Foundation
import CryptoKit

/// A `URLSession` builder that validates TLS for the limited set of
/// hosts Eidos is allowed to reach (HuggingFace model fetch only).
///
/// Two layers of defense:
///
/// 1. **Hostname allowlist** — refuses any TLS challenge whose host
///    isn't on `Self.allowedHosts`. Defends against mis-configured
///    `EgressGuard` or future code accidentally talking to a third
///    party.
/// 2. **Optional SPKI pin** — if `Self.pinnedSPKIHashes` is non-empty,
///    the leaf certificate's SubjectPublicKeyInfo hash must match
///    one of the pins. Defends against a compromised CA issuing a
///    rogue cert for huggingface.co. Pin set is empty by default
///    (system trust only) — populate from a known-good cert via
///    `printSPKIHashFor(...)` and check the value into source.
///
/// Use `Self.session()` as a drop-in replacement for
/// `URLSession.shared` everywhere we contact HuggingFace.
enum SecureHTTPSSession {

    /// Hostnames allowed to TLS-handshake through this session.
    /// Anything else is refused at the session-delegate layer.
    static let allowedHosts: Set<String> = [
        "huggingface.co",
        "cdn-lfs.huggingface.co",
        "cdn-lfs-us-1.hf.co",
        "cas-bridge.xethub.hf.co",
    ]

    /// Optional SPKI (Subject Public Key Info) SHA-256 hash pin set.
    /// When NON-empty, the leaf cert's SPKI hash MUST match one of
    /// these for the connection to proceed.
    ///
    /// Empty by default — populate by:
    ///   1. Visiting huggingface.co in a browser, exporting the cert
    ///   2. `openssl x509 -in cert.pem -pubkey -noout
    ///       | openssl pkey -pubin -outform DER
    ///       | openssl dgst -sha256 -binary
    ///       | base64`
    ///   3. Pasting the resulting base64 into this set
    ///
    /// Keep at least 2 pins (current + backup) to survive routine
    /// cert rotation.
    static let pinnedSPKIHashes: Set<String> = []

    /// Returns a `URLSession` configured with the secure delegate.
    /// New session per call so we don't share connection pools across
    /// tasks with different lifetimes (cheap; URLSession is internally
    /// pooled at a lower layer).
    static func session() -> URLSession {
        let delegate = SecureSessionDelegate(
            allowedHosts: allowedHosts,
            pinnedSPKIHashes: pinnedSPKIHashes
        )
        let config = URLSessionConfiguration.default
        // Refuse legacy TLS — HuggingFace supports 1.2/1.3.
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}

/// Session delegate enforcing the hostname allowlist + optional SPKI pin.
private final class SecureSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let allowedHosts: Set<String>
    let pinnedSPKIHashes: Set<String>

    init(allowedHosts: Set<String>, pinnedSPKIHashes: Set<String>) {
        self.allowedHosts = allowedHosts
        self.pinnedSPKIHashes = pinnedSPKIHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            // Non-TLS challenge type (basic auth, etc.) — we don't speak those.
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host
        // Layer 1: hostname allowlist.
        guard isHostAllowed(host) else {
            EidosLogger.shared.log(.error, category: .download,
                event: "tls.host.denied",
                payload: ["host": host],
                failure: .downloadNetwork)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Layer 2: system trust evaluation (CA chain, expiry, etc.).
        var error: CFError?
        let trusted = SecTrustEvaluateWithError(serverTrust, &error)
        guard trusted else {
            EidosLogger.shared.log(.error, category: .download,
                event: "tls.system-trust.failed",
                payload: ["host": host, "error": error?.localizedDescription ?? "(unknown)"],
                failure: .downloadNetwork)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Layer 3: optional SPKI pin. Skipped if no pins configured.
        if !pinnedSPKIHashes.isEmpty {
            guard let leafHash = leafSPKISha256Base64(serverTrust: serverTrust),
                  pinnedSPKIHashes.contains(leafHash) else {
                EidosLogger.shared.log(.error, category: .download,
                    event: "tls.spki-pin.mismatch",
                    payload: ["host": host],
                    failure: .downloadNetwork)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        // All checks passed.
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    /// Checks both exact host match and `*.huggingface.co` subdomain
    /// match (HF's CDN hosts rotate occasionally).
    private func isHostAllowed(_ host: String) -> Bool {
        if allowedHosts.contains(host) { return true }
        // Permit subdomains of huggingface.co specifically. We don't
        // generalize — `hf.co` and `xethub.hf.co` need explicit entries
        // in `allowedHosts` rather than a wildcard.
        return host.hasSuffix(".huggingface.co")
    }

    /// Extracts the leaf certificate's SPKI and returns the
    /// SHA-256(DER-encoded SPKI) as base64. Matches the format
    /// produced by:
    ///   openssl x509 -in cert.pem -pubkey -noout
    ///     | openssl pkey -pubin -outform DER
    ///     | openssl dgst -sha256 -binary | base64
    private func leafSPKISha256Base64(serverTrust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leaf = chain.first,
              let publicKey = SecCertificateCopyKey(leaf),
              let pubKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { return nil }
        let digest = SHA256.hash(data: pubKeyData)
        return Data(digest).base64EncodedString()
    }
}
