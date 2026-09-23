import XCTest
@testable import MinimalSleep

@MainActor
final class AudioCoordinatorTests: XCTestCase {
    func testBackgroundSchedulerExpiresSessionWithoutUIViewTimer() {
        var now: TimeInterval = 0
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let scheduler = FakeSleepTimerScheduler()
        let coordinator = AudioCoordinator(
            engine: engine,
            scheduler: scheduler,
            timerPolicy: SleepTimerPolicy(
                selectedDuration: .fifteenMinutes,
                monotonicNow: { now }
            )
        )

        coordinator.play(origin: .user)
        XCTAssertEqual(scheduler.startCount, 1)

        now = 900
        scheduler.fireLatest()

        XCTAssertEqual(coordinator.playbackState, .expired)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertGreaterThanOrEqual(scheduler.stopCount, 1)
    }

    func testStaleTimerCallbackCannotExpireReplacementSound() {
        var now: TimeInterval = 0
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let scheduler = FakeSleepTimerScheduler()
        let coordinator = AudioCoordinator(
            engine: engine,
            scheduler: scheduler,
            timerPolicy: SleepTimerPolicy(
                selectedDuration: .fifteenMinutes,
                monotonicNow: { now }
            )
        )

        coordinator.play(origin: .user)
        let staleCallback = scheduler.latestCallback
        coordinator.selectSound(SoundCatalog.builtIn[2])
        XCTAssertEqual(coordinator.playbackState, .playing)

        now = 900
        staleCallback?()
        XCTAssertEqual(coordinator.playbackState, .playing)

        scheduler.fireLatest()
        XCTAssertEqual(coordinator.playbackState, .expired)
    }

    func testSwitchingSoundWhilePausedKeepsDeadlineSchedulerRunning() {
        var now: TimeInterval = 0
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let scheduler = FakeSleepTimerScheduler()
        let coordinator = AudioCoordinator(
            engine: engine,
            scheduler: scheduler,
            timerPolicy: SleepTimerPolicy(
                selectedDuration: .fifteenMinutes,
                monotonicNow: { now }
            )
        )

        coordinator.play()
        coordinator.pause()
        coordinator.selectSound(SoundCatalog.builtIn[2])

        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertEqual(scheduler.startCount, 2)

        now = 900
        scheduler.fireLatest()
        XCTAssertEqual(coordinator.playbackState, .expired)
    }

    func testAudioSessionSafetyEventPausesAndNeverAutoResumes() {
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let coordinator = AudioCoordinator(engine: engine)

        coordinator.play(origin: .user)
        engine.sendSafetyEvent()

        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertEqual(engine.pauseCount, 1)
        XCTAssertEqual(engine.playCount, 1)
    }

    func testRuntimeDecodeFailureStopsSessionAndClearsTimer() {
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let coordinator = AudioCoordinator(engine: engine)

        coordinator.play()
        engine.sendPlaybackFailure("音频解码失败")

        XCTAssertEqual(coordinator.playbackState, .failed("音频解码失败"))
        XCTAssertFalse(coordinator.timerSnapshot.isArmed)
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testImportedSoundLoadsFromItsPrivateFileURL() {
        let engine = FakeAudioPlaybackEngine(loadedSoundID: nil)
        let coordinator = AudioCoordinator(engine: engine)
        let imported = ImportedSound(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            displayName: "我的雨声",
            storedFileName: "private.m4a",
            byteCount: 42
        )
        let privateURL = URL(fileURLWithPath: "/private/application-support/private.m4a")

        coordinator.selectImportedSound(imported, fileURL: privateURL)
        coordinator.play()

        XCTAssertEqual(coordinator.currentImportedSoundID, imported.id)
        XCTAssertEqual(engine.loadedResourceURL, privateURL)
        XCTAssertEqual(coordinator.selectedSound.title, "我的雨声")
    }

    func testPlaybackPreferencesRestoreAndSaveWithoutAutoplay() {
        let preferences = FakePlaybackPreferences(
            selectedDuration: .sixtyMinutes,
            baseVolume: 0.7
        )
        let engine = FakeAudioPlaybackEngine(loadedSoundID: nil)
        let coordinator = AudioCoordinator(engine: engine, preferences: preferences)

        XCTAssertEqual(coordinator.selectedDuration, .sixtyMinutes)
        XCTAssertEqual(coordinator.baseVolume, 0.7, accuracy: 0.001)
        XCTAssertEqual(engine.lastVolume, 0.7, accuracy: 0.001)
        XCTAssertEqual(coordinator.playbackState, .stopped)
        XCTAssertEqual(engine.playCount, 0)

        coordinator.selectDuration(.ninetyMinutes)
        coordinator.setBaseVolume(0.2)

        XCTAssertEqual(preferences.selectedDuration, .ninetyMinutes)
        XCTAssertEqual(preferences.baseVolume ?? -1, 0.2, accuracy: 0.001)
    }

    func testExpiredSessionCannotBeResumedByRemoteCommand() {
        var now: TimeInterval = 0
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let coordinator = AudioCoordinator(
            engine: engine,
            timerPolicy: SleepTimerPolicy(
                selectedDuration: .fifteenMinutes,
                monotonicNow: { now }
            )
        )

        coordinator.play(origin: .user)
        XCTAssertEqual(engine.playCount, 1)

        now = 900
        coordinator.refreshTimer()
        XCTAssertEqual(coordinator.playbackState, .expired)

        coordinator.play(origin: .remoteCommand)
        XCTAssertEqual(engine.playCount, 1)
    }

    func testStoppedSessionCannotBeStartedByRemoteCommand() {
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let coordinator = AudioCoordinator(engine: engine)

        coordinator.play(origin: .remoteCommand)

        XCTAssertEqual(coordinator.playbackState, .stopped)
        XCTAssertEqual(engine.playCount, 0)
    }

    func testStopClearsCurrentCountdown() {
        let engine = FakeAudioPlaybackEngine(loadedSoundID: SoundCatalog.builtIn[0].id)
        let coordinator = AudioCoordinator(engine: engine)

        coordinator.play(origin: .user)
        XCTAssertTrue(coordinator.timerSnapshot.isArmed)

        coordinator.stop()
        XCTAssertFalse(coordinator.timerSnapshot.isArmed)
        XCTAssertNil(coordinator.timerSnapshot.remaining)
    }
}

private final class FakeAudioPlaybackEngine: AudioPlaybackEngine {
    var loadedSoundID: String?
    var onPlaybackMustPause: (() -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var loadedResourceURL: URL?
    private(set) var lastVolume: Float = -1

    init(loadedSoundID: String?) {
        self.loadedSoundID = loadedSoundID
    }

    func load(sound: SoundDescriptor, resourceURL: URL) throws {
        loadedSoundID = sound.id
        loadedResourceURL = resourceURL
    }

    func play() throws { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { stopCount += 1 }
    func setVolume(_ volume: Float) { lastVolume = volume }

    func sendSafetyEvent() {
        onPlaybackMustPause?()
    }

    func sendPlaybackFailure(_ message: String) {
        onPlaybackFailed?(message)
    }
}

@MainActor
private final class FakePlaybackPreferences: PlaybackPreferencesStoring {
    var selectedDuration: SleepDuration?
    var baseVolume: Float?

    init(selectedDuration: SleepDuration?, baseVolume: Float?) {
        self.selectedDuration = selectedDuration
        self.baseVolume = baseVolume
    }
}

@MainActor
private final class FakeSleepTimerScheduler: SleepTimerScheduling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var latestCallback: (() -> Void)?

    func start(tick: @escaping () -> Void) {
        startCount += 1
        latestCallback = tick
    }

    func stop() {
        stopCount += 1
    }

    func fireLatest() {
        latestCallback?()
    }
}
