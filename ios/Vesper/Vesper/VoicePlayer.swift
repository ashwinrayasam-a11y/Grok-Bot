import AVFoundation
import Foundation

/// Plays her voice (MP3 clips from Ara) and tracks which message is speaking.
/// Streamed replies arrive as several sentence clips: the first plays the
/// moment it lands and later clips queue up behind it seamlessly. No transport
/// controls anywhere — tap a bubble to replay from the start.
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingID: UUID?

    private var player: AVAudioPlayer? {
        didSet { meterPlayer = player }
    }
    /// RealityKit's render callback reads the meter from a nonisolated
    /// context. This weak mirror keeps that read Swift 6-legal: it is only
    /// written alongside `player`, and AVAudioPlayer metering is safe to
    /// poll from the render loop.
    private nonisolated(unsafe) weak var meterPlayer: AVAudioPlayer?
    private var queue: [Data] = []

    static func duration(of data: Data) -> Double? {
        (try? AVAudioPlayer(data: data))?.duration
    }

    /// Tap = replay the whole reply from the start.
    func replay(_ message: ChatMessage) {
        let clips = message.voiceClips
        guard !clips.isEmpty else { return }
        start(clips: clips, id: message.id)
    }

    /// Single-clip playback (away mode, non-streamed replies).
    func play(_ data: Data, id: UUID) {
        start(clips: [data], id: id)
    }

    /// Streaming: a new clip for a reply. Starts speaking immediately if this
    /// message isn't already mid-voice; otherwise it queues in order.
    func enqueue(_ data: Data, for id: UUID) {
        if playingID == id {
            queue.append(data)
        } else {
            start(clips: [data], id: id)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        queue = []
        playingID = nil
    }

    private func start(clips: [Data], id: UUID) {
        player?.stop()
        player = nil
        queue = Array(clips.dropFirst())
        playingID = id
        playData(clips[0])
    }

    /// False while TalkSession owns the audio session (Talk mode).
    var managesSession = true

    private func playData(_ data: Data) {
        if managesSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
        }
        guard let newPlayer = try? AVAudioPlayer(data: data) else {
            advance()
            return
        }
        newPlayer.delegate = self
        newPlayer.isMeteringEnabled = true  // drives her mouth while she speaks
        player = newPlayer
        newPlayer.play()
    }

    private func advance() {
        player = nil
        if queue.isEmpty {
            playingID = nil
        } else {
            playData(queue.removeFirst())
        }
    }

    /// Live speech level, 0…1 — polled by the avatar's render loop.
    nonisolated func meterLevel() -> Float {
        guard let player = meterPlayer, player.isPlaying else { return 0 }
        player.updateMeters()
        let decibels = player.averagePower(forChannel: 0)  // -160…0
        return max(0, min(1, (decibels + 42) / 42))
    }

    /// Whether she is audibly speaking right now — safe from the render loop.
    nonisolated var isLive: Bool {
        meterPlayer?.isPlaying ?? false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.advance()
        }
    }
}
