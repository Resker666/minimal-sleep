import XCTest
@testable import MinimalSleep

@MainActor
final class AudioCoordinatorTests: XCTestCase {
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
    private(set) var playCount = 0

    init(loadedSoundID: String?) {
        self.loadedSoundID = loadedSoundID
    }

    func load(sound: SoundDescriptor, resourceURL: URL) throws {
        loadedSoundID = sound.id
    }

    func play() throws { playCount += 1 }
    func pause() {}
    func stop() {}
    func setVolume(_ volume: Float) {}
}
