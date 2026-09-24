import AVFoundation
import Combine
import Foundation

enum RecordingLibraryError: Error, Equatable, LocalizedError {
    case recordingInProgress
    case storageUnavailable
    case missingFile

    var errorDescription: String? {
        switch self {
        case .recordingInProgress: return "请先结束夜间记录，再回听或删除片段"
        case .storageUnavailable: return "本机录音目录不可用"
        case .missingFile: return "声音片段文件已丢失，其他记录仍可查看"
        }
    }
}

@MainActor
protocol RecordingClipPlaying: AnyObject {
    var onFinished: (() -> Void)? { get set }
    func play(url: URL) throws
    func stop()
}

@MainActor
final class AVAudioPlayerRecordingClipPlayer: NSObject, RecordingClipPlaying, AVAudioPlayerDelegate {
    var onFinished: (() -> Void)?
    private var player: AVAudioPlayer?

    func play(url: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        guard player.prepareToPlay(), player.play() else {
            throw AudioPlaybackEngineError.playbackDidNotStart
        }
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.onFinished?()
        }
    }
}

@MainActor
final class RecordingLibrary: ObservableObject {
    @Published private(set) var sessions: [RecordingSessionSummary] = []
    @Published private(set) var selectedSession: RecordingSession?
    @Published private(set) var playingEventID: UUID?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    private let store: RecordingStore?
    private let sleepAudio: AudioCoordinator
    private let audioSession: AudioSessionControlling
    private let clipPlayer: RecordingClipPlaying
    private let isRecording: @MainActor () -> Bool
    private var playingSessionID: UUID?

    init(
        store: RecordingStore?,
        sleepAudio: AudioCoordinator,
        audioSession: AudioSessionControlling,
        clipPlayer: RecordingClipPlaying? = nil,
        isRecording: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.sleepAudio = sleepAudio
        self.audioSession = audioSession
        self.clipPlayer = clipPlayer ?? AVAudioPlayerRecordingClipPlayer()
        self.isRecording = isRecording
        self.clipPlayer.onFinished = { [weak self] in self?.stopPlayback() }
    }

    func reload() async {
        guard let store else {
            errorMessage = RecordingLibraryError.storageUnavailable.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            sessions = try await store.sessions()
            if let selectedSession {
                self.selectedSession = try? await store.session(id: selectedSession.id)
            }
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    func selectSession(id: UUID) async {
        guard let store else {
            errorMessage = RecordingLibraryError.storageUnavailable.localizedDescription
            return
        }
        do {
            selectedSession = try await store.session(id: id)
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    func play(sessionID: UUID, eventID: UUID) async throws {
        do {
            try requireStoppedRecording()
            guard let store else { throw RecordingLibraryError.storageUnavailable }
            let url = try await store.eventFileURL(sessionID: sessionID, eventID: eventID)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw RecordingLibraryError.missingFile
            }
            stopPlayback()
            sleepAudio.pause()
            try audioSession.setPlaybackActive(true)
            do {
                try clipPlayer.play(url: url)
            } catch {
                try? audioSession.setPlaybackActive(false)
                throw error
            }
            playingSessionID = sessionID
            playingEventID = eventID
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
            throw error
        }
    }

    func stopPlayback() {
        guard playingEventID != nil else { return }
        clipPlayer.stop()
        try? audioSession.setPlaybackActive(false)
        playingEventID = nil
        playingSessionID = nil
    }

    func deleteEvent(sessionID: UUID, eventID: UUID) async throws {
        do {
            try requireStoppedRecording()
            guard let store else { throw RecordingLibraryError.storageUnavailable }
            if playingEventID == eventID { stopPlayback() }
            try await store.deleteEvent(sessionID: sessionID, eventID: eventID)
            await reload()
        } catch {
            errorMessage = message(for: error)
            throw error
        }
    }

    func deleteSession(id: UUID) async throws {
        do {
            try requireStoppedRecording()
            guard let store else { throw RecordingLibraryError.storageUnavailable }
            if playingSessionID == id { stopPlayback() }
            try await store.deleteSession(id: id)
            if selectedSession?.id == id { selectedSession = nil }
            await reload()
        } catch {
            errorMessage = message(for: error)
            throw error
        }
    }

    private func requireStoppedRecording() throws {
        if isRecording() { throw RecordingLibraryError.recordingInProgress }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "操作失败，请重试"
    }
}
