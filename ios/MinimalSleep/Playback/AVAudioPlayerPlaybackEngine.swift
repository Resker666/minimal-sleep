import AVFoundation
import Foundation

enum AudioPlaybackEngineError: LocalizedError {
    case playerUnavailable
    case playbackDidNotStart

    var errorDescription: String? {
        switch self {
        case .playerUnavailable:
            return "音频尚未加载"
        case .playbackDidNotStart:
            return "音频无法开始播放"
        }
    }
}

@MainActor
final class AVAudioPlayerPlaybackEngine: NSObject, AudioPlaybackEngine, AVAudioPlayerDelegate {
    private(set) var loadedSoundID: String?
    var onPlaybackMustPause: (() -> Void)?
    var onPlaybackFailed: ((String) -> Void)?

    private let sessionController: AudioSessionControlling
    private var player: AVAudioPlayer?
    private var volume: Float = 0.5

    init(sessionController: AudioSessionControlling) {
        self.sessionController = sessionController
        super.init()
    }

    func load(sound: SoundDescriptor, resourceURL: URL) throws {
        let player = try AVAudioPlayer(contentsOf: resourceURL)
        player.delegate = self
        player.numberOfLoops = -1
        player.volume = volume
        guard player.prepareToPlay() else {
            throw AudioPlaybackEngineError.playerUnavailable
        }
        self.player = player
        loadedSoundID = sound.id
    }

    func play() throws {
        guard let player else { throw AudioPlaybackEngineError.playerUnavailable }
        try sessionController.setPlaybackActive(true)
        guard player.play() else {
            try? sessionController.setPlaybackActive(false)
            throw AudioPlaybackEngineError.playbackDidNotStart
        }
    }

    func pause() {
        player?.pause()
        try? sessionController.setPlaybackActive(false)
    }

    func stop() {
        player?.stop()
        player = nil
        loadedSoundID = nil
        try? sessionController.setPlaybackActive(false)
    }

    func setVolume(_ volume: Float) {
        self.volume = min(1, max(0, volume))
        player?.volume = self.volume
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.onPlaybackFailed?("音频解码失败，请重新选择声音")
        }
    }
}
