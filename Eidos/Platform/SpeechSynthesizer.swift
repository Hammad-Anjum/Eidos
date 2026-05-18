import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Wraps `AVSpeechSynthesizer` for speaking Gemma's reply aloud.
///
/// Used by Med Mode so a label transcription is read out without the user
/// needing to look at the screen — and by any future flow that flips
/// `EidosFeatureFlags.shared.speakRepliesEnabled` on.
///
/// Design notes:
/// - System framework only (no extra dependencies, no network).
/// - Voice quality is `.default`. Premium voices (`.quality == .premium`)
///   sound noticeably better but require the user to download them per
///   language in iOS Settings → Accessibility → Spoken Content. We pick
///   the best installed voice for the language at speak time, so once
///   the user adds premium voices the wrapper auto-uses them.
/// - Speech rate respects the user's system-wide preferred rate via
///   `AVSpeechUtteranceDefaultSpeechRate`. Custom rate control is exposed
///   via the `rateMultiplier` parameter (1.0 = system default).
/// - We share one synthesizer instance because `AVSpeechSynthesizer`
///   serializes utterances internally; calling `speak` while another
///   utterance is in flight enqueues correctly. `cancel()` flushes the
///   queue immediately.
@MainActor
final class SpeechSynthesizer {

    /// Shared instance. There is exactly one synthesizer per app launch
    /// — AVSpeechSynthesizer is heavyweight (audio session ownership)
    /// and supports queueing internally.
    static let shared = SpeechSynthesizer()

    private let synth = AVSpeechSynthesizer()

    /// The most recently spoken utterance text, exposed so the
    /// "Repeat last description" Action / rotor entry can replay it.
    private(set) var lastSpokenText: String?

    private init() {}

    /// Speak `text` in `languageCode` (BCP-47, e.g. `"en-US"`, `"es-MX"`,
    /// `"ar"`).
    ///
    /// `rateMultiplier` 1.0 = system-default rate; 0.5 = half speed;
    /// 1.5 = one and a half times. Clamped to AVSpeechUtterance's
    /// supported range.
    func speak(
        _ text: String,
        languageCode: String = "en-US",
        rateMultiplier: Float = 1.0
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = bestVoice(for: languageCode)
        utterance.rate = clampedRate(rateMultiplier)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0

        lastSpokenText = trimmed
        synth.speak(utterance)
    }

    /// Speak the last text again. No-op if nothing has been spoken yet.
    func repeatLast(languageCode: String = "en-US",
                    rateMultiplier: Float = 1.0) {
        guard let last = lastSpokenText else { return }
        speak(last, languageCode: languageCode, rateMultiplier: rateMultiplier)
    }

    /// Cancel any in-progress + queued utterances immediately. Called
    /// from "stop generating" + when a new turn starts.
    func cancel() {
        synth.stopSpeaking(at: .immediate)
    }

    /// True if `synth` is actively producing audio.
    var isSpeaking: Bool { synth.isSpeaking }

    // MARK: - Voice selection

    /// Picks the best available voice for `languageCode`, preferring
    /// premium > enhanced > default quality. Falls back to the system
    /// default voice if no match is installed.
    private func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Exact match first (e.g. "es-MX"), then language-only ("es"),
        // then fall back to the system default for that language.
        let candidates = voices.filter {
            $0.language == languageCode
                || $0.language.hasPrefix(languageCode + "-")
                || $0.language.hasPrefix(languageCode.prefix(2))
        }
        if candidates.isEmpty {
            return AVSpeechSynthesisVoice(language: languageCode)
        }

        // Prefer premium > enhanced > default.
        let ranked = candidates.sorted { lhs, rhs in
            qualityRank(lhs.quality) > qualityRank(rhs.quality)
        }
        return ranked.first
    }

    private func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium:  return 3
        case .enhanced: return 2
        case .default:  return 1
        @unknown default: return 0
        }
    }

    private func clampedRate(_ multiplier: Float) -> Float {
        let target = AVSpeechUtteranceDefaultSpeechRate * multiplier
        return max(AVSpeechUtteranceMinimumSpeechRate,
                   min(AVSpeechUtteranceMaximumSpeechRate, target))
    }
}
