import Foundation
import Speech
import AVFoundation

@MainActor
@Observable
final class SpeechTranscriber {
    var transcript = ""
    var isRecording = false
    var error: String?

    init() {}

    func requestPermission() async -> Bool {
        // TODO(phase 3)
        false
    }

    func start() throws {
        // TODO(phase 3)
    }

    func stop() {
        // TODO(phase 3)
    }
}
