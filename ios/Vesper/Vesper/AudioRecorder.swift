import AVFoundation
import Foundation

/// Tap-on / tap-off microphone capture. Records 16 kHz mono WAV — exactly what
/// Whisper wants — and never touches Apple's speech recognizer, so nothing
/// gets censored on the way out of your mouth.
@MainActor
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    /// Live mic level, 0…1, for the listening bar.
    @Published var level: Double = 0
    @Published var deniedReason: String?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var fileURL: URL?

    func start() async {
        guard !isRecording else { return }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            deniedReason = "She needs microphone access to hear you (Settings → Privacy → Microphone)."
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vesper-say-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else {
                deniedReason = "Couldn't start the microphone."
                return
            }
            recorder = newRecorder
            fileURL = url
            isRecording = true
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.readLevel() }
            }
        } catch {
            deniedReason = "Couldn't open the microphone: \(error.localizedDescription)"
        }
    }

    private func readLevel() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0)) // -160…0
        level = max(0, min(1, (decibels + 50) / 50))
    }

    /// Stop and hand back the clip. Returns nil for blips too short to mean anything.
    func stop() -> URL? {
        guard isRecording else { return nil }
        let duration = recorder?.currentTime ?? 0
        tearDown()
        guard duration > 0.4, let url = fileURL else {
            if let url = fileURL { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return url
    }

    /// Discard the take entirely.
    func cancel() {
        guard isRecording else { return }
        tearDown()
        recorder = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }

    private func tearDown() {
        isRecording = false
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
