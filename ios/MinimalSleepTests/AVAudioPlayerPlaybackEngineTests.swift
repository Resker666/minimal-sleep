import AVFoundation
import XCTest
@testable import MinimalSleep

@MainActor
final class AVAudioPlayerPlaybackEngineTests: XCTestCase {
    func testPauseAndStopReleaseOnlyPlaybackPurpose() throws {
        let session = FakePlaybackSessionController()
        let engine = AVAudioPlayerPlaybackEngine(sessionController: session)
        let sound = SoundCatalog.builtIn[4]
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: sound.resourceBaseName, withExtension: sound.resourceExtension
        ))

        try engine.load(sound: sound, resourceURL: url)
        try engine.play()
        engine.pause()
        try engine.play()
        engine.stop()

        XCTAssertEqual(session.playbackStates, [true, false, true, false])
        XCTAssertNil(engine.loadedSoundID)
    }
}

@MainActor
private final class FakePlaybackSessionController: AudioSessionControlling {
    var onSafetyEvent: ((AudioSafetyEvent) -> Void)?
    private(set) var playbackStates: [Bool] = []

    func setPlaybackActive(_ active: Bool) throws {
        playbackStates.append(active)
    }

    func setRecordingActive(_ active: Bool) throws { }
}
