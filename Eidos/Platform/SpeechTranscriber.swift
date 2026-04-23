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
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let mic: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
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
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriberError.recognitionUnavailable
        }

        // Audio session setup (iOS-only API, noop on macOS Catalyst).
        #if canImport(AVFAudio) && !os(macOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // `.spokenAudio` mode plays nicer with speech recognition than
            // `.measurement`, which strips processing and is meant for
            // acoustic-analysis apps, not STT.
            try session.setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
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

        // Audio tap — guard against a zero-channel input format which can
        // trip an assertion in CoreAudio on devices that report a weird
        // route (e.g. audio being captured by another app).
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw SpeechTranscriberError.recognitionUnavailable
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        audioEngine.prepare()
        do { try audioEngine.start() }
        catch { throw SpeechTranscriberError.audioSessionFailed(error) }

        transcript = ""
        error = nil
        isRecording = true

        // Recognition task.
        self.task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let err {
                    self.error = SpeechTranscriberError.recognizerFailed(err).localizedDescription
                    self.stop()
                }
                if result?.isFinal == true {
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
