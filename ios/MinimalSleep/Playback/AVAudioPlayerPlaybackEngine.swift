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

    private let session: AVAudioSession
    private var player: AVAudioPlayer?
    private var volume: Float = 0.5

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        super.init()

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChangeNotification(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        guard player.play() else {
            throw AudioPlaybackEngineError.playbackDidNotStart
        }
    }

    func pause() {
        player?.pause()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stop() {
        player?.stop()
        player = nil
        loadedSoundID = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setVolume(_ volume: Float) {
        self.volume = min(1, max(0, volume))
        player?.volume = self.volume
    }

    @objc
    nonisolated private func handleInterruptionNotification(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
        Task { @MainActor [weak self] in
            self?.onPlaybackMustPause?()
        }
    }

    @objc
    nonisolated private func handleRouteChangeNotification(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in
            self?.onPlaybackMustPause?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.onPlaybackFailed?("音频解码失败，请重新选择声音")
        }
    }
}
