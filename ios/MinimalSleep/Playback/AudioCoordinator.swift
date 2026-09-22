import Combine
import Foundation

protocol AudioPlaybackEngine: AnyObject {
    var loadedSoundID: String? { get }
    func load(sound: SoundDescriptor, resourceURL: URL) throws
    func play() throws
    func pause()
    func stop()
    func setVolume(_ volume: Float)
}

// TODO（需 Mac 编译）: Add the AVFoundation-backed AudioPlaybackEngine on the Mac.
// It must own the only AVAudioPlayer, configure AVAudioSession as .playback, loop
// indefinitely, and forward interruption/old-device-unavailable events here.

@MainActor
final class AudioCoordinator: ObservableObject {
    enum PlaybackState: Equatable {
        case stopped
        case loading
        case playing
        case paused
        case expired
        case failed(String)
    }

    enum PlayOrigin: Equatable {
        case user
        case remoteCommand
    }

    enum CoordinatorError: LocalizedError {
        case playbackAdapterUnavailable
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .playbackAdapterUnavailable:
                return "播放组件尚未接入"
            case let .missingResource(name):
                return "缺少音频资源：\(name)"
            }
        }
    }

    @Published private(set) var playbackState: PlaybackState = .stopped
    @Published private(set) var selectedSound = SoundCatalog.builtIn[0]
    @Published private(set) var timerSnapshot = SleepTimerSnapshot(
        isArmed: false,
        remaining: nil,
        fadeGain: 1,
        isExpired: false
    )
    @Published private(set) var baseVolume: Float = 0.5

    var selectedDuration: SleepDuration { timerPolicy.selectedDuration }
    var isPlaying: Bool { playbackState == .playing }

    private let engine: AudioPlaybackEngine?
    private let resourceBundle: Bundle
    private let nowPlaying: NowPlayingController
    private var timerPolicy: SleepTimerPolicy
    private var sessionGeneration = 0

    init(
        engine: AudioPlaybackEngine? = nil,
        resourceBundle: Bundle = .main,
        nowPlaying: NowPlayingController = NowPlayingController(),
        timerPolicy: SleepTimerPolicy = SleepTimerPolicy()
    ) {
        self.engine = engine
        self.resourceBundle = resourceBundle
        self.nowPlaying = nowPlaying
        self.timerPolicy = timerPolicy
        self.timerSnapshot = timerPolicy.snapshot()

        nowPlaying.configureRemoteCommands(
            onPlay: { [weak self] in self?.play(origin: .remoteCommand) },
            onPause: { [weak self] in self?.pause() }
        )
    }

    func selectSound(_ sound: SoundDescriptor) {
        guard sound != selectedSound else { return }
        let shouldResume = playbackState == .playing
        let shouldRemainPaused = playbackState == .paused
        sessionGeneration += 1
        engine?.stop()
        selectedSound = sound
        playbackState = shouldResume ? .loading : (shouldRemainPaused ? .paused : .stopped)
        if shouldResume {
            play(origin: .user)
        } else if shouldRemainPaused {
            publishNowPlaying()
        } else {
            nowPlaying.clear()
        }
    }

    func selectDuration(_ duration: SleepDuration) {
        let active = timerSnapshot.isArmed
        timerPolicy.select(duration, whileSessionIsActive: active)
        refreshTimer()
    }

    func setBaseVolume(_ value: Float) {
        baseVolume = min(1, max(0, value))
        applyEffectiveVolume()
    }

    func play(origin: PlayOrigin = .user) {
        if origin == .remoteCommand {
            guard playbackState == .paused, !timerPolicy.snapshot().isExpired else { return }
        }

        guard let engine else {
            playbackState = .failed(CoordinatorError.playbackAdapterUnavailable.localizedDescription)
            return
        }

        if origin == .user && (playbackState == .stopped || playbackState == .expired) {
            sessionGeneration += 1
            timerPolicy.start()
        } else if !timerPolicy.snapshot().isArmed {
            timerPolicy.start()
        }

        do {
            if engine.loadedSoundID != selectedSound.id {
                playbackState = .loading
                guard let url = resourceBundle.url(
                    forResource: selectedSound.resourceBaseName,
                    withExtension: selectedSound.resourceExtension
                ) else {
                    throw CoordinatorError.missingResource(
                        "\(selectedSound.resourceBaseName).\(selectedSound.resourceExtension)"
                    )
                }
                try engine.load(sound: selectedSound, resourceURL: url)
            }
            try engine.play()
            playbackState = .playing
            refreshTimer()
            publishNowPlaying()
        } catch {
            engine.stop()
            timerPolicy.stop()
            refreshTimer()
            playbackState = .failed(error.localizedDescription)
            nowPlaying.clear()
        }
    }

    func pause() {
        guard playbackState == .playing || playbackState == .loading else { return }
        engine?.pause()
        timerPolicy.pause()
        playbackState = .paused
        refreshTimer()
        publishNowPlaying()
    }

    func stop() {
        sessionGeneration += 1
        engine?.stop()
        timerPolicy.stop()
        playbackState = .stopped
        refreshTimer()
        nowPlaying.clear()
    }

    func handleInterruptionOrUnsafeRouteChange() {
        // Never auto-resume after a call, another app's interruption, or headphone removal.
        pause()
    }

    func refreshTimer() {
        // TODO（需 Mac 编译）: Call this from an audio-session-owned background-safe
        // scheduler while a session is armed. SwiftUI's display timer is not the owner.
        let snapshot = timerPolicy.snapshot()
        timerSnapshot = snapshot
        applyEffectiveVolume()
        guard snapshot.isExpired, playbackState != .expired else { return }

        sessionGeneration += 1
        engine?.stop()
        playbackState = .expired
        nowPlaying.clear()
    }

    private func applyEffectiveVolume() {
        let gain = Float(timerPolicy.snapshot().fadeGain)
        engine?.setVolume(baseVolume * gain)
    }

    private func publishNowPlaying() {
        nowPlaying.publish(
            .init(
                title: selectedSound.title,
                attribution: selectedSound.attribution,
                isPlaying: playbackState == .playing
            )
        )
    }
}
