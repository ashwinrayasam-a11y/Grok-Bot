import AVFoundation
import Foundation

/// Plays her voice bubbles (MP3 data from Ara) and tracks which one is speaking.
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingID: UUID?

    private var player: AVAudioPlayer?

    static func duration(of data: Data) -> Double? {
        (try? AVAudioPlayer(data: data))?.duration
    }

    /// Tap = replay from the start. No transport controls, like a voice note.
    func replay(_ message: ChatMessage) {
        guard let data = message.audio else { return }
        play(data, id: message.id)
    }

    func play(_ data: Data, id: UUID) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        guard let newPlayer = try? AVAudioPlayer(data: data) else { return }
        newPlayer.delegate = self
        player = newPlayer
        newPlayer.play()
        playingID = id
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.playingID = nil
        }
    }
}
