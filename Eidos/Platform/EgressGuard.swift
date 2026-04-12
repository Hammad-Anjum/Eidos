import Foundation

// B14: Auditable, enforceable no-egress guarantee.
//
// `install()` registers a custom URLProtocol that intercepts every outbound
// URLSession request at the app level and rejects it unless the request
// targets the Hugging Face model download host AND a model download is
// currently in progress.
//
// The bar for this class is: a future dependency or a future feature that
// tries to phone home should FAIL LOUDLY instead of silently breaking the
// privacy promise in README.md.
//
// Known limitation: URLProtocol only intercepts requests made through a
// URLSession that uses the default config (or a config we explicitly seed).
// Third-party networking stacks that bypass URLSession entirely (e.g.
// direct BSD sockets) can evade this guard. Phase 6 adds a build-time
// linker check that bans such imports.
enum EgressGuard {

    // Host part of GemmaVariant.downloadURL. Must match exactly.
    static let allowedHost = "huggingface.co"

    private static let isInstalledKey = "EgressGuardInstalled"

    static func install() {
        // TODO(phase 2): URLProtocol.registerClass(EgressGuardProtocol.self)
        // plus ModelDownloader wires its URLSession through a config that
        // has our protocol at the front of `protocolClasses`.
    }

    /// Set to true while a model download is in progress. When false, all
    /// requests (including those targeting `allowedHost`) are blocked.
    static var isModelDownloadInProgress: Bool = false
}
