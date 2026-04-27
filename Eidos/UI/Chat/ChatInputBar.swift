import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Chat composer with mic + camera + photo picker + text + send.
///
/// Layout (left → right):
///   [📷 camera] [📁 photo] [🎙️ mic] [text field] [➤ send]
///
/// When the user attaches an image (camera or photo), we show a small
/// thumbnail above the text field and keep it until send. The parent
/// view model wires the image into `GemmaSession.generate(images:)`
/// via the multimodal pipeline.
struct ChatInputBar: View {
    @Binding var text: String
    @Binding var attachedImage: CGImage?
    @Binding var attachedAudio: Data?
    @FocusState.Binding var focused: Bool
    let isGenerating: Bool
    let onSend: () -> Void

    @State private var transcriber = SpeechTranscriber()
    @State private var audioCapture = AudioCaptureService()

    @State private var showCamera = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var visionService = VisionCaptureService()

    var body: some View {
        VStack(spacing: 6) {
            if let attached = attachedImage {
                attachmentPreview(attached)
            }
            if let audio = attachedAudio {
                audioAttachmentPreview(audio)
            }

            HStack(alignment: .bottom, spacing: 6) {
                cameraButton
                photoPickerButton
                micButton

                ZStack(alignment: .topLeading) {
                    if text.isEmpty && !isRecordingAudio {
                        Text("Message Eidos")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .lineLimit(1...6)
                        .disabled(isGenerating || isRecordingAudio)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(focused ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1.5)
                )

                sendButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .onChange(of: transcriber.transcript) { _, newValue in
            if transcriber.isRecording { text = newValue }
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView(
                onCaptured: { cg in
                    attachedImage = cg
                    showCamera = false
                    EidosLogger.shared.metric(.ui, event: "vision.camera.captured",
                        values: ["w": cg.width, "h": cg.height])
                },
                onCancelled: { showCamera = false }
            )
        }
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task {
                if let cg = try? await visionService.loadImage(from: selection) {
                    attachedImage = cg
                }
                photoSelection = []
            }
        }
    }

    // MARK: - Attachment preview

    @ViewBuilder
    private func attachmentPreview(_ cg: CGImage) -> some View {
        HStack {
            #if canImport(UIKit)
            Image(uiImage: UIImage(cgImage: cg))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            #endif
            Text("Attached image — Gemma will see it")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                attachedImage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func audioAttachmentPreview(_ audio: Data) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor.opacity(0.9))
            Text("Attached voice note — \(audioDurationLabel(for: audio))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                attachedAudio = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Camera

    private var cameraButton: some View {
        Button {
            showCamera = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .frame(width: 36, height: 36)
        }
        .disabled(isGenerating || !visionService.cameraAvailable)
        .opacity(visionService.cameraAvailable ? 1 : 0.35)
        .accessibilityLabel("Take photo")
    }

    // MARK: - Photo picker

    private var photoPickerButton: some View {
        PhotosPicker(selection: $photoSelection, maxSelectionCount: 1, matching: .images) {
            Image(systemName: "photo.fill.on.rectangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .frame(width: 36, height: 36)
        }
        .disabled(isGenerating)
        .accessibilityLabel("Pick photo")
    }

    // MARK: - Mic

    private var micButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            Image(systemName: isRecordingAudio ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(isRecordingAudio ? Color.red : Color.accentColor.opacity(0.9))
                .symbolEffect(.pulse, options: .repeating, isActive: isRecordingAudio)
        }
        .disabled(isGenerating)
        .frame(width: 36, height: 36)
        .accessibilityLabel(isRecordingAudio ? "Stop recording" : "Start voice input")
    }

    // MARK: - Send

    private var sendButton: some View {
        Button(action: onSend) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: canSend
                                ? [.accentColor, Color.accentColor.opacity(0.8)]
                                : [Color.secondary.opacity(0.3), Color.secondary.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .disabled(!canSend)
        .accessibilityLabel("Send")
    }

    /// Can send when there's either text OR an attached image, and we're
    /// not mid-generation / mid-recording.
    private var canSend: Bool {
        (!text.isEmpty || attachedImage != nil || attachedAudio != nil) && !isGenerating && !isRecordingAudio
    }

    private var isRecordingAudio: Bool {
        transcriber.isRecording || audioCapture.isRecording
    }

    // MARK: - Voice

    @MainActor
    private func toggleRecording() async {
        if EidosFeatureFlags.shared.audioViaGemmaEnabled && GemmaSession.supportsNativeAudioInput {
            await toggleGemmaAudio()
        } else {
            await toggleTranscriber()
        }
    }

    @MainActor
    private func toggleTranscriber() async {
        if transcriber.isRecording {
            transcriber.stop()
            return
        }
        let ok = await transcriber.requestPermission()
        guard ok else { return }
        do { try transcriber.start() }
        catch { /* surfaced via transcriber.error */ }
    }

    @MainActor
    private func toggleGemmaAudio() async {
        if audioCapture.isRecording {
            let buffer = (try? await audioCapture.stopAndReturnBuffer()) ?? Data()
            if buffer.isEmpty {
                EidosLogger.shared.log(.warn, category: .chat, event: "audio.empty")
                return
            }
            attachedAudio = buffer
            EidosLogger.shared.metric(.chat, event: "audio.ready", values: [
                "bytes": buffer.count,
            ])
            return
        }
        do {
            attachedAudio = nil
            try await audioCapture.requestPermission()
            try audioCapture.start()
        } catch {
            EidosLogger.shared.error(.chat, event: "audio.start.failed",
                error: error, failure: .audioSessionFailed)
        }
    }

    private func audioDurationLabel(for audio: Data) -> String {
        let seconds = Double(audio.count) / (16_000 * 2)
        return String(format: "%.1fs", seconds)
    }
}
