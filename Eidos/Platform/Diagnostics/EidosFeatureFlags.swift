import Foundation

/// Runtime-toggleable capability flags.
///
/// Feature flags let us ship partially-finished subsystems without
/// exposing them to users (ship-dark), and let engineering turn off a
/// misbehaving subsystem in a hotfix without a full rebuild.
///
/// Backing store is `UserDefaults` so flags survive relaunch; we mirror
/// a "dev defaults" overlay that can be forced on via `#if DEBUG`.
///
/// All reads are `@MainActor` — this is UI-adjacent config, and we
/// don't want to deal with cross-thread UserDefaults reads.
@MainActor
@Observable
final class EidosFeatureFlags {

    /// Shared instance. There is exactly one set of flags per app launch.
    static let shared = EidosFeatureFlags()

    // MARK: - Flag keys

    private enum Key: String {
        case visionEnabled = "eidos.flag.vision"
        case audioEnabled = "eidos.flag.audio"
        case reasoningEnabled = "eidos.flag.reasoning"
        case personasEnabled = "eidos.flag.personas"
        case diagnosticsUIEnabled = "eidos.flag.diagnosticsUI"
        case longContextPackingEnabled = "eidos.flag.longContext"
        case safetyGateEnabled = "eidos.flag.safetyGate"
        case audioViaGemmaEnabled = "eidos.flag.audioViaGemma"
        case minimalChatPromptEnabled = "eidos.flag.minimalChatPrompt"
    }

    // MARK: - Flags

    /// Accept images as input to Gemma. Requires `MLXVLM` and a vision-
    /// capable model variant. Off until Phase 8's VLM upgrade validates.
    var visionEnabled: Bool {
        get { bool(.visionEnabled, default: defaultOn) }
        set { set(.visionEnabled, newValue) }
    }

    /// Primary voice path uses Gemma's native audio input
    /// (`audioViaGemmaEnabled` = true) or falls back to
    /// `SFSpeechRecognizer` transcription (false).
    var audioViaGemmaEnabled: Bool {
        get { bool(.audioViaGemmaEnabled, default: false) }
        set { set(.audioViaGemmaEnabled, newValue) }
    }

    /// Enables the new `AudioCaptureService` + in-memory PCM pipeline.
    /// Without this, the legacy `SpeechTranscriber` is used.
    var audioEnabled: Bool {
        get { bool(.audioEnabled, default: defaultOn) }
        set { set(.audioEnabled, newValue) }
    }

    /// Opt-in chain-of-thought prompting. Slower but higher-quality
    /// for digest, persona dispatch, and skill conflict resolution.
    var reasoningEnabled: Bool {
        get { bool(.reasoningEnabled, default: defaultOn) }
        set { set(.reasoningEnabled, newValue) }
    }

    /// Persona / skills system (Phase 9). Off until Phase 9 lands.
    var personasEnabled: Bool {
        get { bool(.personasEnabled, default: false) }
        set { set(.personasEnabled, newValue) }
    }

    /// Settings → Diagnostics sub-panel visibility. Always on in DEBUG,
    /// hidden in RELEASE until the user 5-taps the app version.
    var diagnosticsUIEnabled: Bool {
        get { bool(.diagnosticsUIEnabled, default: defaultOn) }
        set { set(.diagnosticsUIEnabled, newValue) }
    }

    /// Pack more memory into prompts (up to ~15 K tokens of context)
    /// instead of aggressive RAG filtering. Exploits Gemma 4's 128 K
    /// context — but **dramatically increases KV-cache RAM usage**
    /// (~1 GB at 15 K tokens for E2B).
    ///
    /// Default: **OFF** even in DEBUG. On devices with limited memory
    /// headroom (Mac Designed-for-iPad, iPhone 13/14/15 with 6 GB RAM)
    /// turning this on alongside the 3.58 GB Gemma E2B weights can
    /// trigger jetsam / OOM kills. Opt in via Settings → Diagnostics →
    /// Flags once you've measured your device's headroom.
    var longContextPackingEnabled: Bool {
        get { bool(.longContextPackingEnabled, default: false) }
        set { set(.longContextPackingEnabled, newValue) }
    }

    /// Use a slim system prompt + bypass RAG/ambient/tools/history when
    /// running a chat turn. **Default ON in iPhone RELEASE** to keep the
    /// prefill KV cache inside Metal's heap budget — the full prompt
    /// (system identity + RAG context + ambient + tool schemas + history)
    /// can hit 10–15 K tokens, which spikes the GPU buffer past the
    /// foreground-app ceiling on iPhone and gets the process reaped by the
    /// kernel before Gemma emits a single token. Briefing path is
    /// unaffected — it builds its own slim prompt.
    ///
    /// When ON: chat builds `[system: short-id, user: text]` only.
    /// When OFF (Mac, iPad, DEBUG): full RAG/tool pipeline as before.
    var minimalChatPromptEnabled: Bool {
        get {
            // RELEASE on iPhone defaults ON; everywhere else defaults OFF.
            #if DEBUG
            let def = false
            #else
            let def: Bool = (DeviceProfile.formFactor == .iPhone)
            #endif
            return bool(.minimalChatPromptEnabled, default: def)
        }
        set { set(.minimalChatPromptEnabled, newValue) }
    }

    /// Hardcoded pre-LLM safety refusal for crisis / medical / legal.
    /// **Must never be user-toggleable in RELEASE builds.** Debug only.
    ///
    /// In RELEASE builds the getter always returns `true` and the setter
    /// is a no-op — safety is not user-toggleable in production.
    var safetyGateEnabled: Bool {
        get {
            #if DEBUG
            return bool(.safetyGateEnabled, default: true)
            #else
            return true
            #endif
        }
        set {
            #if DEBUG
            set(.safetyGateEnabled, newValue)
            #endif
        }
    }

    // MARK: - Helpers

    /// Whether flags default on in development builds. In release builds,
    /// new flags default OFF so we ship-dark safely.
    private var defaultOn: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private func bool(_ key: Key, default def: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key.rawValue) == nil {
            return def
        }
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }

    private func set(_ key: Key, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    /// Resets every flag to its built-in default. Exposed to Diagnostics
    /// UI for quick recovery from a botched manual toggle.
    func resetAll() {
        for key in [
            Key.visionEnabled,
            .audioEnabled,
            .reasoningEnabled,
            .personasEnabled,
            .diagnosticsUIEnabled,
            .longContextPackingEnabled,
            .safetyGateEnabled,
            .audioViaGemmaEnabled,
            .minimalChatPromptEnabled,
        ] {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }
}
