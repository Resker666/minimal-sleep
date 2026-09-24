import Combine
import Foundation
import XCTest
@testable import MinimalSleep

@MainActor
final class NightRecordingCoordinatorTests: XCTestCase {
    func testGrantedPermissionStartsAndStopsRecording() async {
        let harness = Harness(permission: .granted)
        await harness.coordinator.start()
        XCTAssertEqual(harness.coordinator.state, .recording)
        XCTAssertEqual(harness.capture.startCount, 1)
        XCTAssertEqual(harness.session.recordingStates, [true])

        await harness.coordinator.stop()
        XCTAssertEqual(harness.coordinator.state, .stopped)
        XCTAssertEqual(harness.session.recordingStates, [true, false])
        let statuses = await harness.store.finishedStatuses
        XCTAssertEqual(statuses, [.completed])
    }

    func testDeniedPermissionNeverStartsCapture() async {
        let harness = Harness(permission: .denied)
        await harness.coordinator.start()
        if case .failed = harness.coordinator.state { } else {
            XCTFail("Denied permission should show a failure")
        }
        XCTAssertEqual(harness.capture.startCount, 0)
        XCTAssertTrue(harness.session.recordingStates.isEmpty)
    }

    func testRepeatedStartKeepsOneCaptureStream() async {
        let harness = Harness(permission: .granted)
        await harness.coordinator.start()
        await harness.coordinator.start()
        XCTAssertEqual(harness.capture.startCount, 1)
        await harness.coordinator.stop()
    }

    func testStopWhilePermissionIsPendingPreventsLateStart() async {
        let harness = Harness(permission: .notDetermined)
        harness.permission.suspendRequest = true
        let starting = Task { await harness.coordinator.start() }
        await Task.yield()
        XCTAssertEqual(harness.coordinator.state, .requestingPermission)

        await harness.coordinator.stop()
        harness.permission.resolveRequest(granted: true)
        await starting.value

        XCTAssertEqual(harness.coordinator.state, .stopped)
        XCTAssertEqual(harness.capture.startCount, 0)
    }

    func testSpaceErrorBeforeCaptureLeavesNoActiveAudioSession() async {
        let harness = Harness(permission: .granted)
        await harness.store.failStart()
        await harness.coordinator.start()

        if case .failed = harness.coordinator.state { } else {
            XCTFail("Insufficient space should fail the start")
        }
        XCTAssertEqual(harness.capture.startCount, 0)
        XCTAssertTrue(harness.session.recordingStates.isEmpty)
    }

    func testFrameErrorInterruptsSessionAndReleasesAudioSession() async {
        let harness = Harness(permission: .granted)
        await harness.coordinator.start()
        let failure = expectation(description: "frame failure is surfaced")
        let subscription = harness.coordinator.$state.sink { state in
            if case .failed = state { failure.fulfill() }
        }
        harness.capture.fail()
        await fulfillment(of: [failure], timeout: 3)
        subscription.cancel()

        let statuses = await harness.store.finishedStatuses
        XCTAssertEqual(statuses, [.interrupted])
        XCTAssertEqual(harness.session.recordingStates, [true, false])
    }

    func testSafetyEventStopsAndNeverRestartsAfterRecoveryNotice() async {
        let harness = Harness(permission: .granted)
        await harness.coordinator.start()
        await harness.coordinator.handleSafetyEvent(.oldDeviceUnavailable)

        XCTAssertEqual(harness.capture.startCount, 1)
        let statuses = await harness.store.finishedStatuses
        XCTAssertEqual(statuses, [.interrupted])
        XCTAssertEqual(harness.session.recordingStates, [true, false])
        if case .interrupted = harness.coordinator.state { } else {
            XCTFail("Unsafe route should remain interrupted")
        }
        await Task.yield()
        XCTAssertEqual(harness.capture.startCount, 1)
    }

    func testSharedSafetyCallbackPausesPlaybackAndStopsRecording() async {
        let harness = Harness(permission: .granted)
        let playbackEngine = FakeBridgePlaybackEngine()
        let playback = AudioCoordinator(engine: playbackEngine)
        AudioSafetyBridge.connect(
            session: harness.session, playback: playback, recording: harness.coordinator
        )
        playback.play()
        await harness.coordinator.start()
        let stopped = expectation(description: "recording stopped after interruption")
        let subscription = harness.coordinator.$state.sink { state in
            if case .interrupted = state { stopped.fulfill() }
        }

        harness.session.onSafetyEvent?(.interruptionBegan)
        await fulfillment(of: [stopped], timeout: 3)
        subscription.cancel()

        XCTAssertEqual(playback.playbackState, .paused)
        XCTAssertEqual(playbackEngine.pauseCount, 1)
        let statuses = await harness.store.finishedStatuses
        XCTAssertEqual(statuses, [.interrupted])
    }
}

@MainActor
private struct Harness {
    let permission: FakeMicrophonePermission
    let capture: FakeMicrophoneCapture
    let store: FakeCoordinatorRecordingStore
    let session: FakeCoordinatorAudioSession
    let coordinator: NightRecordingCoordinator

    init(permission value: MicrophonePermission) {
        let permission = FakeMicrophonePermission(value: value)
        let capture = FakeMicrophoneCapture()
        let store = FakeCoordinatorRecordingStore()
        let session = FakeCoordinatorAudioSession()
        self.permission = permission
        self.capture = capture
        self.store = store
        self.session = session
        coordinator = NightRecordingCoordinator(
            permission: permission,
            capture: capture,
            store: store,
            audioSession: session,
            playbackSnapshot: {
                RecordingPlaybackSnapshot(isPlaying: false, soundID: "white-noise", appVolume: 0)
            }
        )
    }
}

@MainActor
private final class FakeMicrophonePermission: MicrophonePermissionProviding {
    var value: MicrophonePermission
    var suspendRequest = false
    private var pending: CheckedContinuation<Bool, Never>?

    init(value: MicrophonePermission) { self.value = value }
    func status() -> MicrophonePermission { value }
    func request() async -> Bool {
        if suspendRequest {
            return await withCheckedContinuation { pending = $0 }
        }
        return value == .granted
    }
    func resolveRequest(granted: Bool) {
        value = granted ? .granted : .denied
        pending?.resume(returning: granted)
        pending = nil
    }
}

@MainActor
private final class FakeMicrophoneCapture: MicrophoneCapturing {
    enum FrameFailure: Error { case expected }
    private(set) var startCount = 0
    private var continuation: AsyncThrowingStream<[Int16], Error>.Continuation?

    func makeFrames() throws -> AsyncThrowingStream<[Int16], Error> {
        startCount += 1
        return AsyncThrowingStream { continuation = $0 }
    }
    func stop() { continuation?.finish() }
    func fail() { continuation?.finish(throwing: FrameFailure.expected) }
}

@MainActor
private final class FakeCoordinatorAudioSession: AudioSessionControlling {
    var onSafetyEvent: ((AudioSafetyEvent) -> Void)?
    private(set) var recordingStates: [Bool] = []
    func setPlaybackActive(_ active: Bool) throws { }
    func setRecordingActive(_ active: Bool) throws { recordingStates.append(active) }
}

private actor FakeCoordinatorRecordingStore: RecordingStoring {
    private(set) var finishedStatuses: [RecordingSessionStatus] = []
    private var shouldFailStart = false
    func failStart() { shouldFailStart = true }
    func startSession(id: UUID, at: Date, timeZoneIdentifier: String) throws -> RecordingSession {
        if shouldFailStart { throw RecordingStoreError.insufficientFreeSpace }
        return RecordingSession(id: id, startedAt: at, timeZoneIdentifier: timeZoneIdentifier)
    }
    func appendSegment(
        _ segment: RecordingAudioSegment, to sessionID: UUID,
        playbackAffected: Bool, createdAt: Date
    ) throws -> RecordingEvent {
        RecordingEvent(
            id: UUID(), sessionID: sessionID, groupID: segment.groupID,
            startSample: segment.startSample, sampleCount: Int64(segment.samples.count),
            fileName: "fake.wav", playbackAffected: playbackAffected, createdAt: createdAt
        )
    }
    func replacePlaybackIntervals(
        _ intervals: [RecordingPlaybackInterval], capturedSamples: Int64, for sessionID: UUID
    ) throws { }
    func finishSession(
        id: UUID, at date: Date, status: RecordingSessionStatus, reason: String?,
        capturedSamples: Int64, playbackIntervals: [RecordingPlaybackInterval]
    ) throws { finishedStatuses.append(status) }
    func deleteSession(id: UUID) throws { }
}

@MainActor
private final class FakeBridgePlaybackEngine: AudioPlaybackEngine {
    var loadedSoundID: String? = SoundCatalog.builtIn[0].id
    var onPlaybackMustPause: (() -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    private(set) var pauseCount = 0
    func load(sound: SoundDescriptor, resourceURL: URL) throws { loadedSoundID = sound.id }
    func play() throws { }
    func pause() { pauseCount += 1 }
    func stop() { }
    func setVolume(_ volume: Float) { }
}
