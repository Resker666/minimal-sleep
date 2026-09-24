import SwiftUI

@main
@MainActor
struct MinimalSleepApp: App {
    @StateObject private var audioCoordinator: AudioCoordinator
    @StateObject private var importedLibrary: ImportedSoundLibrary
    @StateObject private var nightRecordingCoordinator: NightRecordingCoordinator
    private let recordingStore: RecordingStore?

    init() {
        let sessionController = AudioSessionController()
        let coordinator = AudioCoordinator(
            engine: AVAudioPlayerPlaybackEngine(sessionController: sessionController),
            preferences: UserDefaultsPlaybackPreferences()
        )
        let concreteStore = try? RecordingStore(
            fileSystem: FileManagerRecordingFileSystem.applicationSupport()
        )
        let recording = NightRecordingCoordinator(
            permission: AVAudioApplicationMicrophonePermission(),
            capture: AVAudioEngineMicrophoneCaptureEngine(),
            store: concreteStore ?? UnavailableRecordingStore(),
            audioSession: sessionController,
            playbackSnapshot: { [weak coordinator] in
                coordinator?.recordingPlaybackSnapshot ?? RecordingPlaybackSnapshot(
                    isPlaying: false, soundID: "", appVolume: 0
                )
            }
        )
        AudioSafetyBridge.connect(
            session: sessionController, playback: coordinator, recording: recording
        )
        recordingStore = concreteStore
        _audioCoordinator = StateObject(wrappedValue: coordinator)
        _nightRecordingCoordinator = StateObject(wrappedValue: recording)
        _importedLibrary = StateObject(
            wrappedValue: ImportedSoundLibrary(playbackController: coordinator)
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                coordinator: audioCoordinator,
                importedLibrary: importedLibrary
            )
            .preferredColorScheme(.dark)
        }
    }
}

private actor UnavailableRecordingStore: RecordingStoring {
    private var unavailable: Error {
        NSError(
            domain: "MinimalSleep.RecordingStorage", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "无法创建本机录音目录，请检查设备存储空间"]
        )
    }

    func startSession(id: UUID, at: Date, timeZoneIdentifier: String) throws -> RecordingSession {
        throw unavailable
    }
    func appendSegment(
        _ segment: RecordingAudioSegment, to sessionID: UUID,
        playbackAffected: Bool, createdAt: Date
    ) throws -> RecordingEvent { throw unavailable }
    func replacePlaybackIntervals(
        _ intervals: [RecordingPlaybackInterval], capturedSamples: Int64, for sessionID: UUID
    ) throws { throw unavailable }
    func finishSession(
        id: UUID, at date: Date, status: RecordingSessionStatus, reason: String?,
        capturedSamples: Int64, playbackIntervals: [RecordingPlaybackInterval]
    ) throws { throw unavailable }
    func deleteSession(id: UUID) throws { throw unavailable }
}
