import Combine
import Foundation

@MainActor
protocol AudioPlaybackEngine: AnyObject {
    var loadedSoundID: String? { get }
    var onPlaybackMustPause: (() -> Void)? { get set }
    var onPlaybackFailed: ((String) -> Void)? { get set }
    func load(sound: SoundDescriptor, resourceURL: URL) throws
    func play() throws
    func pause()
    func stop()
    func setVolume(_ volume: Float)
}

@MainActor
protocol SleepTimerScheduling: AnyObject {
    func start(tick: @escaping () -> Void)
    func stop()
}

@MainActor
final class DispatchSleepTimerScheduler: SleepTimerScheduling {
    private var timer: DispatchSourceTimer?

    func start(tick: @escaping () -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(250),
            repeating: .milliseconds(250),
            leeway: .milliseconds(50)
        )
        timer.setEventHandler(handler: tick)
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}

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
    var currentImportedSoundID: UUID? { selectedSound.importedSoundID }

    private let engine: AudioPlaybackEngine?
    private let resourceBundle: Bundle
    private let nowPlaying: NowPlayingControlling
    private let scheduler: SleepTimerScheduling
    private let preferences: PlaybackPreferencesStoring?
    private var timerPolicy: SleepTimerPolicy
    private var sessionGeneration = 0

    init(
        engine: AudioPlaybackEngine? = nil,
        resourceBundle: Bundle = .main,
        nowPlaying: NowPlayingControlling? = nil,
        scheduler: SleepTimerScheduling? = nil,
        preferences: PlaybackPreferencesStoring? = nil,
        timerPolicy: SleepTimerPolicy = SleepTimerPolicy()
    ) {
        self.engine = engine
        self.resourceBundle = resourceBundle
        self.nowPlaying = nowPlaying ?? NowPlayingController()
        self.scheduler = scheduler ?? DispatchSleepTimerScheduler()
        self.preferences = preferences
        var restoredPolicy = timerPolicy
        if let savedDuration = preferences?.selectedDuration {
            restoredPolicy.select(savedDuration, whileSessionIsActive: false)
        }
        self.timerPolicy = restoredPolicy
        self.timerSnapshot = restoredPolicy.snapshot()
        self.baseVolume = min(1, max(0, preferences?.baseVolume ?? 0.5))
        self.engine?.setVolume(self.baseVolume)

        self.nowPlaying.configureRemoteCommands(
            onPlay: { [weak self] in self?.play(origin: .remoteCommand) },
            onPause: { [weak self] in self?.pause() }
        )
        self.engine?.onPlaybackMustPause = { [weak self] in
            self?.handleInterruptionOrUnsafeRouteChange()
        }
        self.engine?.onPlaybackFailed = { [weak self] message in
            self?.handlePlaybackFailure(message)
        }
    }

    func selectSound(_ sound: SoundDescriptor) {
        guard sound != selectedSound else { return }
        let shouldResume = playbackState == .playing
        let shouldRemainPaused = playbackState == .paused
        sessionGeneration += 1
        scheduler.stop()
        engine?.stop()
        selectedSound = sound
        playbackState = shouldResume ? .loading : (shouldRemainPaused ? .paused : .stopped)
        if shouldResume {
            play(origin: .user)
        } else if shouldRemainPaused {
            publishNowPlaying()
            scheduleTimerIfNeeded()
        } else {
            nowPlaying.clear()
        }
    }

    func selectImportedSound(_ sound: ImportedSound, fileURL: URL) {
        selectSound(.imported(sound, fileURL: fileURL))
    }

    func selectDuration(_ duration: SleepDuration) {
        let active = playbackState == .playing
            || playbackState == .paused
            || playbackState == .loading
        if active {
            sessionGeneration += 1
            scheduler.stop()
        }
        timerPolicy.select(duration, whileSessionIsActive: active)
        preferences?.selectedDuration = duration
        refreshTimer()
        scheduleTimerIfNeeded()
    }

    func setBaseVolume(_ value: Float) {
        baseVolume = min(1, max(0, value))
        preferences?.baseVolume = baseVolume
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

        if origin == .user && (
            playbackState == .stopped
                || playbackState == .expired
                || timerPolicy.snapshot().isExpired
        ) {
            sessionGeneration += 1
            timerPolicy.start()
        } else if !timerPolicy.snapshot().isArmed {
            timerPolicy.start()
        }

        do {
            if engine.loadedSoundID != selectedSound.id {
                playbackState = .loading
                guard let url = selectedSound.directResourceURL ?? resourceBundle.url(
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
            scheduleTimerIfNeeded()
            publishNowPlaying()
        } catch {
            engine.stop()
            timerPolicy.stop()
            scheduler.stop()
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
        scheduler.stop()
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

    func handlePlaybackFailure(_ message: String) {
        sessionGeneration += 1
        scheduler.stop()
        engine?.stop()
        timerPolicy.stop()
        playbackState = .failed(message)
        refreshTimer()
        nowPlaying.clear()
    }

    func refreshTimer() {
        let snapshot = timerPolicy.snapshot()
        timerSnapshot = snapshot
        applyEffectiveVolume()
        guard snapshot.isExpired, playbackState != .expired else { return }

        sessionGeneration += 1
        scheduler.stop()
        engine?.stop()
        playbackState = .expired
        nowPlaying.clear()
    }

    private func applyEffectiveVolume() {
        let gain = Float(timerPolicy.snapshot().fadeGain)
        engine?.setVolume(baseVolume * gain)
    }

    private func scheduleTimerIfNeeded() {
        scheduler.stop()
        guard timerSnapshot.isArmed, timerSnapshot.remaining != nil else { return }

        let generation = sessionGeneration
        scheduler.start { [weak self] in
            guard let self, self.sessionGeneration == generation else { return }
            self.refreshTimer()
        }
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

extension AudioCoordinator: ImportedPlaybackControlling {
    func stopIfPlayingImportedSound(id: UUID) {
        guard currentImportedSoundID == id else { return }
        stop()
        selectSound(SoundCatalog.builtIn[0])
    }
}
