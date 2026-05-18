import Foundation
import Speech
import AVFoundation

enum SpeechTranscriberError: Error, LocalizedError {
    case recognitionUnavailable
    case notAuthorized
    case audioSessionFailed(Error)
    case recognizerFailed(Error)

    var errorDescription: String? {
        switch self {
        case .recognitionUnavailable: "Speech recognition isn't available on this device."
        case .notAuthorized: "Microphone or speech-recognition permission was denied."
        case .audioSessionFailed(let e): "Couldn't start the audio session: \(e.localizedDescription)"
        case .recognizerFailed(let e): "Speech recognizer failed: \(e.localizedDescription)"
        }
    }
}

/// On-device speech-to-text via `SFSpeechRecognizer` with
/// `requiresOnDeviceRecognition = true`. No audio or transcript ever
/// leaves the device — aligns with the "zero egress" guarantee.
///
/// Lifecycle:
/// 1. `requestPermission()` once on first use.
/// 2. `start()` streams mic audio into the recognizer. `transcript`
///    updates incrementally as partial results arrive.
/// 3. `stop()` ends the session; `transcript` holds the final text.
@MainActor
@Observable
final class SpeechTranscriber {

    var transcript = ""
    var isRecording = false
    var error: String?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        // Simulator: pretend permission was granted so the UI flow is
        // testable. Real permission prompts on simulator can hang or
        // crash in CoreAudio.
        #if targetEnvironment(simulator)
        return true
        #else
        EidosLogger.shared.log(.info, category: .permission,
            event: "speech.permission.request.start")

        // CRITICAL: the TCC permission callbacks (`SFSpeechRecognizer`,
        // `AVAudioApplication`) fire on `com.apple.root.default-qos`,
        // NOT on MainActor. Without the explicit `@Sendable` on these
        // closures, the Swift 6 runtime treats them as MainActor-isolated
        // (inherited from this enclosing `@MainActor` method) and
        // `swift_task_isCurrentExecutorWithFlagsImpl` traps when TCC
        // invokes them off-main → EXC_BREAKPOINT. Same crash class as
        // `DeviceProfile.formFactor` had before v6. The fix is to mark
        // the inner closures `@Sendable` so they don't inherit isolation.
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                cont.resume(returning: status == .authorized)
            }
        }
        EidosLogger.shared.log(.info, category: .permission,
            event: "speech.permission.speech-step", payload: ["granted": speech])

        let mic: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                cont.resume(returning: granted)
            }
        }
        EidosLogger.shared.log(.info, category: .permission,
            event: "speech.permission.mic-step", payload: ["granted": mic])

        return speech && mic
        #endif
    }

    // MARK: - Start / stop

    func start() throws {
        guard !isRecording else { return }

        // Simulator has no real mic input. `AVAudioEngine.inputNode` can
        // trap with EXC_BREAKPOINT in CoreAudio because the simulator's
        // virtual input device returns a zero-channel format; `installTap`
        // then fails an internal assertion. Short-circuit with a canned
        // transcript so the voice → chat flow stays testable without a
        // physical device.
        #if targetEnvironment(simulator)
        transcript = ""
        error = nil
        isRecording = true
        Task { @MainActor [weak self] in
            let canned = "This is a simulator voice test. On a real iPhone, this text is your speech."
            for word in canned.split(separator: " ") {
                try? await Task.sleep(nanoseconds: 180_000_000)  // 180 ms / word
                guard let self, self.isRecording else { return }
                if self.transcript.isEmpty {
                    self.transcript = String(word)
                } else {
                    self.transcript += " " + String(word)
                }
            }
            // Auto-stop after the canned transcript completes.
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.stop()
        }
        return
        #else
        EidosLogger.shared.log(.info, category: .chat, event: "speech.start.entry")

        guard let recognizer, recognizer.isAvailable else {
            EidosLogger.shared.log(.warn, category: .chat,
                event: "speech.start.recognizer-unavailable",
                failure: .audioSessionFailed)
            throw SpeechTranscriberError.recognitionUnavailable
        }

        // Audio session setup (iOS-only API, noop on macOS Catalyst).
        // We FIRST deactivate any stale session — a previous crashed
        // session may have left `setActive(true)` lingering in CoreAudio,
        // and re-activating without deactivation can deadlock or crash.
        #if canImport(AVFAudio) && !os(macOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // Best-effort deactivate first; ignore errors — common when
            // there's nothing to deactivate, which is the expected case.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            // `.measurement` mode is the correct mode for `.record`
            // category. The previous code used `.spokenAudio`, which is
            // intended for **playback** (audiobooks, podcasts) and
            // returns `OSStatus -50` (paramErr) on iOS 26.3.1 when paired
            // with `.record` — we saw 30+ consecutive failures in the
            // tester logs. Apple's own SFSpeechRecognizer sample uses
            // `.record` + `.measurement` + `.duckOthers`. Yes, the
            // documentation says `.measurement` "strips processing" —
            // that's exactly what on-device speech-to-text wants
            // (no AGC, no echo cancellation, raw PCM into the recognizer).
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            EidosLogger.shared.log(.info, category: .chat, event: "speech.start.audio-session.ok")
        } catch {
            EidosLogger.shared.error(.chat, event: "speech.start.audio-session.fail",
                error: error, failure: .audioSessionFailed)
            throw SpeechTranscriberError.audioSessionFailed(error)
        }
        #endif

        // Request — keep partials so the UI can show live text.
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req

        // Audio tap — guard against a zero-channel input format AND
        // against a sample-rate of zero. Both can trip an assertion in
        // CoreAudio's installTap on devices that report a weird route
        // (e.g. audio being captured by another app, mic permission
        // mid-init, or post-crash sandbox state).
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        EidosLogger.shared.log(.info, category: .chat, event: "speech.start.node.format",
            payload: ["channels": format.channelCount, "sample_rate": format.sampleRate])
        guard format.channelCount > 0, format.sampleRate > 0 else {
            EidosLogger.shared.log(.warn, category: .chat,
                event: "speech.start.bad-format",
                payload: ["channels": format.channelCount, "sample_rate": format.sampleRate],
                failure: .audioSessionFailed)
            throw SpeechTranscriberError.recognitionUnavailable
        }
        // CoreAudio invokes the tap on its render thread — NOT MainActor.
        // Mark `@Sendable` so the closure doesn't inherit this method's
        // MainActor isolation and trap when CoreAudio calls it.
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak req] buffer, _ in
            req?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            EidosLogger.shared.log(.info, category: .chat, event: "speech.start.engine.ok")
        } catch {
            EidosLogger.shared.error(.chat, event: "speech.start.engine.fail",
                error: error, failure: .audioSessionFailed)
            // Engine failed to start — clean up the tap so we don't leak
            // a half-attached node.
            node.removeTap(onBus: 0)
            throw SpeechTranscriberError.audioSessionFailed(error)
        }

        transcript = ""
        error = nil
        isRecording = true

        // Recognition task. Same `@Sendable` rule — the SFSpeechRecognizer
        // callback fires off MainActor and the closure must not inherit
        // MainActor isolation, otherwise we trap on `assumeIsolated`.
        //
        // We extract every value we care about into Sendable locals
        // BEFORE hopping to the MainActor Task. `SFSpeechRecognitionResult`
        // and `Error` aren't Sendable themselves, so handing them into
        // a `@MainActor in` closure is a data race per Swift 6 strict
        // concurrency.
        self.task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, err in
            let transcript: String? = result?.bestTranscription.formattedString
            let isFinal: Bool = result?.isFinal ?? false
            let errorMessage: String? = err.map {
                SpeechTranscriberError.recognizerFailed($0).localizedDescription
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let transcript {
                    self.transcript = transcript
                }
                if let errorMessage {
                    self.error = errorMessage
                    self.stop()
                }
                if isFinal {
                    self.stop()
                }
            }
        }
        #endif
    }

    func stop() {
        guard isRecording else { return }
        #if targetEnvironment(simulator)
        isRecording = false
        #else
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        #endif
    }
}
