import AVFoundation
import Foundation
import Speech

/// Hold-to-talk: on-device transcription with the iOS Speech framework.
/// Nothing leaves the phone until you let go.
@MainActor
final class SpeechRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var deniedReason: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    /// True while the finger is down; permission prompts can outlive the press.
    private var pressActive = false

    func begin() async {
        guard !isRecording else { return }
        pressActive = true

        guard let recognizer, recognizer.isAvailable else {
            deniedReason = "Speech recognition isn't available on this device right now."
            return
        }

        let speechAuthorized = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAuthorized, micAllowed else {
            deniedReason = "She needs microphone and speech permissions to hear you (Settings → Privacy)."
            return
        }
        // Finger already lifted (e.g. during the permission prompt)? Don't start.
        guard pressActive else { return }

        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        request = newRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            newRequest.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            deniedReason = "Couldn't open the microphone: \(error.localizedDescription)"
            request = nil
            return
        }

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in
                self?.transcript = text
            }
        }
        isRecording = true
    }

    /// Finger lifted before recording actually started.
    func abortPress() {
        pressActive = false
    }

    /// Stop and hand back whatever she heard.
    func finish() -> String {
        pressActive = false
        guard isRecording else { return "" }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
