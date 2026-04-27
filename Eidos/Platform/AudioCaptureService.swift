import Foundation
@preconcurrency import AVFoundation

/// Errors that `AudioCaptureService` can surface to its caller.
enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case sessionFailed(Error)
    case engineFailed(Error)
    case formatUnavailable
    case captureStopped

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone permission was denied."
        case .sessionFailed(let e): "Audio session failed: \(e.localizedDescription)"
        case .engineFailed(let e): "Audio engine failed: \(e.localizedDescription)"
        case .formatUnavailable: "No audio input format available on this device."
        case .captureStopped: "Audio capture was stopped before producing a buffer."
        }
    }

    /// Maps to a typed `FailureCategory` for logger payloads.
    var failureCategory: FailureCategory {
        switch self {
        case .permissionDenied: .permissionDenied
        case .sessionFailed: .audioSessionFailed
        case .engineFailed: .audioSessionFailed
        case .formatUnavailable: .audioSessionFailed
        case .captureStopped: .audioSessionFailed
        }
    }
}

/// Records mic audio into an in-memory PCM buffer suitable for passing
/// directly to Gemma 4's native audio input.
///
/// Design decisions:
///   - **Disk-free.** Audio never touches the filesystem. The buffer is
///     held in memory, returned to the caller, then freed.
///   - **Fixed format.** We request 16 kHz mono Int16 PCM — the common
///     denominator for speech-LLM audio input. If the engine can't
///     deliver that directly we convert via `AVAudioConverter`.
///   - **VAD-aware.** Optional auto-stop on silence; the caller can also
///     stop manually.
///   - **Sim-safe.** On iOS Simulator, returns a canned buffer to avoid
///     the CoreAudio zero-channel trap that crashes `installTap`.
///
/// Usage:
/// ```
/// let service = AudioCaptureService()
/// try await service.requestPermission()
/// try service.start()
/// // ... observe `rmsLevel` for UI visualizer ...
/// let pcm = try await service.stopAndReturnBuffer()
/// ```
@MainActor
@Observable
final class AudioCaptureService {

    /// Peak RMS level (0...1) of the last captured block. Drives a live
    /// waveform visualizer.
    var rmsLevel: Float = 0

    /// True while the engine is running.
    var isRecording: Bool = false

    /// Duration of the captured audio so far, in seconds.
    var capturedSeconds: Double = 0

    /// Max clip duration before we auto-stop to keep Gemma inputs sane.
    var maxSeconds: Double = 30.0

    /// If true, auto-stop on detected silence after `silenceHangMs`
    /// of continuous low-level audio. Requires `AVAudioApplication`
    /// and works best on iOS 18+.
    var autoStopOnSilence: Bool = true
    var silenceHangMs: Double = 800

    // MARK: - Private

    private let engine = AVAudioEngine()
    private var buffer = Data()
    private var sampleRate: Double = 16_000
    private var targetFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )
    }
    private var lastAboveSilenceAt: Date?
    private var startedAt: Date?
    private var continuation: CheckedContinuation<Data, Error>?

    // MARK: - Permission

    /// Prompts for microphone permission if not yet determined.
    func requestPermission() async throws {
        #if targetEnvironment(simulator)
        // Simulator never blocks on real permission — sandbox has the
        // host Mac's mic but prompts are flaky.
        return
        #elseif os(iOS)
        let granted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        if !granted {
            EidosLogger.shared.log(.warn, category: .permission, event: "audio.permission.denied")
            throw AudioCaptureError.permissionDenied
        }
        #endif
    }

    // MARK: - Lifecycle

    /// Starts the capture. Returns immediately; audio flows into an
    /// internal buffer you retrieve by calling `stopAndReturnBuffer()`.
    func start() throws {
        guard !isRecording else { return }
        buffer.removeAll(keepingCapacity: true)
        capturedSeconds = 0
        startedAt = Date()
        lastAboveSilenceAt = Date()
        rmsLevel = 0

        #if targetEnvironment(simulator)
        isRecording = true
        // Produce a short canned PCM buffer so the downstream Gemma
        // pipeline can be exercised end-to-end on the sim.
        let seconds = 2.0
        let total = Int(seconds * sampleRate)
        var samples = [Int16](repeating: 0, count: total)
        for i in 0..<total {
            // ~440 Hz sine wave for a recognisable "tone" test.
            let t = Double(i) / sampleRate
            samples[i] = Int16(Double(Int16.max) * 0.3 * sin(2 * .pi * 440 * t))
        }
        buffer = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        capturedSeconds = seconds
        EidosLogger.shared.log(.info, category: .chat, event: "audio.capture.simulator")
        return
        #elseif os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioCaptureError.sessionFailed(error)
        }

        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.channelCount > 0, hwFormat.sampleRate > 0 else {
            throw AudioCaptureError.formatUnavailable
        }

        // `AVAudioConverter` resamples / repacks from hw format to
        // 16 kHz mono Int16 on every buffer callback.
        guard let targetFormat else {
            throw AudioCaptureError.formatUnavailable
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw AudioCaptureError.formatUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] pcm, _ in
            self?.handleBuffer(pcm, converter: converter)
        }

        engine.prepare()
        do { try engine.start() }
        catch { throw AudioCaptureError.engineFailed(error) }
        isRecording = true
        EidosLogger.shared.log(.info, category: .chat, event: "audio.capture.start",
            payload: ["sr": targetFormat.sampleRate, "hw_sr": hwFormat.sampleRate])
        #endif
    }

    /// Stops capture and returns the accumulated PCM buffer.
    func stopAndReturnBuffer() async throws -> Data {
        guard isRecording else { return buffer }
        #if targetEnvironment(simulator)
        isRecording = false
        return buffer
        #elseif os(iOS)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        deactivateAudioSession(event: "audio.capture.deactivate_failed")
        EidosLogger.shared.metric(.chat, event: "audio.capture.finish", values: [
            "duration_s": capturedSeconds,
            "bytes": buffer.count,
        ])
        return buffer
        #else
        isRecording = false
        return buffer
        #endif
    }

    /// Cancels the capture without producing a buffer.
    func cancel() {
        guard isRecording else { return }
        #if os(iOS) && !targetEnvironment(simulator)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        deactivateAudioSession(event: "audio.capture.cancel_deactivate_failed")
        #endif
        isRecording = false
        buffer.removeAll()
    }

    // MARK: - Private

    private func handleBuffer(_ pcm: AVAudioPCMBuffer, converter: AVAudioConverter) {
        // Convert to 16 kHz mono Int16.
        guard let targetFormat else {
            EidosLogger.shared.log(
                .error,
                category: .chat,
                event: "audio.capture.target_format_unavailable",
                failure: .audioSessionFailed
            )
            return
        }
        let ratio = targetFormat.sampleRate / pcm.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(1, outCapacity)) else {
            EidosLogger.shared.log(
                .error,
                category: .chat,
                event: "audio.capture.output_buffer_unavailable",
                failure: .audioSessionFailed
            )
            return
        }
        var err: NSError?
        let status = converter.convert(to: outBuf, error: &err) { _, input in
            input.pointee = .haveData
            return pcm
        }
        guard status != .error, err == nil else {
            EidosLogger.shared.log(
                .error,
                category: .chat,
                event: "audio.capture.convert_failed",
                message: err?.localizedDescription,
                failure: .audioSessionFailed
            )
            return
        }

        // Append raw int16 bytes to our buffer.
        if let int16 = outBuf.int16ChannelData?.pointee {
            let count = Int(outBuf.frameLength)
            let bytes = UnsafeBufferPointer(start: int16, count: count)
            buffer.append(contentsOf: Data(buffer: bytes))
        }

        // Compute RMS on the new block for UI + VAD.
        let rms = Self.computeRMS(outBuf)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rmsLevel = rms
            self.capturedSeconds = Double(self.buffer.count) / (self.sampleRate * 2) // int16 = 2 bytes

            if rms > 0.02 {
                self.lastAboveSilenceAt = Date()
            } else if
                self.autoStopOnSilence,
                let last = self.lastAboveSilenceAt,
                Date().timeIntervalSince(last) * 1000 > self.silenceHangMs,
                self.capturedSeconds > 0.5
            {
                // Auto-stop — downstream code will detect isRecording=false.
                self.engine.pause()
                self.engine.stop()
                self.engine.inputNode.removeTap(onBus: 0)
                self.isRecording = false
            }

            if self.capturedSeconds >= self.maxSeconds {
                self.engine.stop()
                self.engine.inputNode.removeTap(onBus: 0)
                self.isRecording = false
            }
        }
    }

    private func deactivateAudioSession(event: String) {
        #if os(iOS) && !targetEnvironment(simulator)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            EidosLogger.shared.error(.chat, event: event, error: error, failure: .audioSessionFailed)
        }
        #endif
    }

    private static func computeRMS(_ buf: AVAudioPCMBuffer) -> Float {
        guard let data = buf.int16ChannelData?.pointee else { return 0 }
        let n = Int(buf.frameLength)
        guard n > 0 else { return 0 }
        var sum: Double = 0
        for i in 0..<n {
            let v = Double(data[i]) / Double(Int16.max)
            sum += v * v
        }
        return Float(sqrt(sum / Double(n)))
    }
}
