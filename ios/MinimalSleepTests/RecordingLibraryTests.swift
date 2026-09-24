import AVFoundation
import XCTest
@testable import MinimalSleep

@MainActor
final class RecordingLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinimalSleepRecordingLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testPlayingEventPausesSleepSoundAndDoesNotAutoResume() async throws {
        let fixture = try await Fixture(root: directory)
        fixture.audio.play()
        XCTAssertEqual(fixture.audio.playbackState, .playing)

        try await fixture.library.play(sessionID: fixture.sessionID, eventID: fixture.event.id)
        XCTAssertEqual(fixture.audio.playbackState, .paused)
        XCTAssertEqual(fixture.library.playingEventID, fixture.event.id)
        XCTAssertEqual(fixture.session.playbackStates.last, true)

        fixture.library.stopPlayback()
        XCTAssertEqual(fixture.audio.playbackState, .paused)
        XCTAssertNil(fixture.library.playingEventID)
        XCTAssertEqual(fixture.session.playbackStates.last, false)
    }

    func testDeletingPlayingEventStopsPlayerBeforeStoreDelete() async throws {
        let fixture = try await Fixture(root: directory)
        let fileURL = try await fixture.store.eventFileURL(
            sessionID: fixture.sessionID, eventID: fixture.event.id
        )
        fixture.clip.onStop = {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
        try await fixture.library.play(sessionID: fixture.sessionID, eventID: fixture.event.id)

        try await fixture.library.deleteEvent(sessionID: fixture.sessionID, eventID: fixture.event.id)

        XCTAssertEqual(fixture.clip.stopCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let stored = try await fixture.store.session(id: fixture.sessionID)
        XCTAssertTrue(stored.events.isEmpty)
    }

    func testRecordingDisablesPlaybackAndDeletion() async throws {
        let fixture = try await Fixture(root: directory)
        fixture.isRecording.value = true

        do {
            try await fixture.library.play(sessionID: fixture.sessionID, eventID: fixture.event.id)
            XCTFail("Playback must be disabled while recording")
        } catch { XCTAssertEqual(error as? RecordingLibraryError, .recordingInProgress) }
        do {
            try await fixture.library.deleteEvent(sessionID: fixture.sessionID, eventID: fixture.event.id)
            XCTFail("Deletion must be disabled while recording")
        } catch { XCTAssertEqual(error as? RecordingLibraryError, .recordingInProgress) }
        XCTAssertEqual(fixture.clip.playCount, 0)
        let stored = try await fixture.store.session(id: fixture.sessionID)
        XCTAssertEqual(stored.eventCount, 1)
    }

    func testReloadShowsSessionAndSelectedEvents() async throws {
        let fixture = try await Fixture(root: directory)
        await fixture.library.reload()
        XCTAssertEqual(fixture.library.sessions.map(\.id), [fixture.sessionID])
        await fixture.library.selectSession(id: fixture.sessionID)
        XCTAssertEqual(fixture.library.selectedSession?.events.map(\.id), [fixture.event.id])
    }
}

@MainActor
private final class RecordingFlag { var value = false }

@MainActor
private struct Fixture {
    let store: RecordingStore
    let sessionID: UUID
    let event: RecordingEvent
    let audio: AudioCoordinator
    let session: FakeLibraryAudioSession
    let clip: FakeClipPlayer
    let isRecording: RecordingFlag
    let library: RecordingLibrary

    init(root: URL) async throws {
        store = RecordingStore(fileSystem: try FileManagerRecordingFileSystem(rootURL: root))
        sessionID = UUID()
        _ = try await store.startSession(id: sessionID, at: Date(), timeZoneIdentifier: "UTC")
        event = try await store.appendSegment(
            RecordingAudioSegment(groupID: UUID(), startSample: 0, samples: [1_000, 2_000]),
            to: sessionID, playbackAffected: false, createdAt: Date()
        )
        audio = AudioCoordinator(engine: FakeLibraryPlaybackEngine())
        session = FakeLibraryAudioSession()
        clip = FakeClipPlayer()
        let flag = RecordingFlag()
        isRecording = flag
        library = RecordingLibrary(
            store: store, sleepAudio: audio, audioSession: session, clipPlayer: clip,
            isRecording: { flag.value }
        )
    }
}

@MainActor
private final class FakeLibraryPlaybackEngine: AudioPlaybackEngine {
    var loadedSoundID: String? = SoundCatalog.builtIn[0].id
    var onPlaybackMustPause: (() -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    func load(sound: SoundDescriptor, resourceURL: URL) throws { loadedSoundID = sound.id }
    func play() throws { }
    func pause() { }
    func stop() { }
    func setVolume(_ volume: Float) { }
}

@MainActor
private final class FakeLibraryAudioSession: AudioSessionControlling {
    var onSafetyEvent: ((AudioSafetyEvent) -> Void)?
    private(set) var playbackStates: [Bool] = []
    func setPlaybackActive(_ active: Bool) throws { playbackStates.append(active) }
    func setRecordingActive(_ active: Bool) throws { }
}

@MainActor
private final class FakeClipPlayer: RecordingClipPlaying {
    var onFinished: (() -> Void)?
    private(set) var playCount = 0
    private(set) var stopCount = 0
    var onStop: (() -> Void)?
    func play(url: URL) throws { playCount += 1 }
    func stop() { stopCount += 1; onStop?() }
}
