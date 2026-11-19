import Combine
import Foundation

enum MicrophonePermission: Equatable {
    case notDetermined
    case denied
    case granted
}

@MainActor
protocol MicrophonePermissionProviding {
    func status() -> MicrophonePermission
    func request() async -> Bool
}

@MainActor
protocol MicrophoneCapturing: AnyObject {
    func makeFrames() throws -> AsyncThrowingStream<[Int16], Error>
    func stop()
}

@MainActor
final class NightRecordingCoordinator: ObservableObject {
    enum State: Equatable {
        case stopped
        case requestingPermission
        case starting
        case recording
        case stopping
        case interrupted(String)
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var capturedSamples: Int64 = 0
    @Published private(set) var eventCount = 0
    private(set) var currentSessionID: UUID?

    private let permission: MicrophonePermissionProviding
    private let capture: MicrophoneCapturing
    private let store: RecordingStoring
    private let audioSession: AudioSessionControlling
    private let playbackSnapshot: @MainActor () -> RecordingPlaybackSnapshot
    private var pipeline: RecordingPipeline?
    private var consumeTask: Task<Void, Never>?
    private var cancelRequested = false
    private var pendingReason: String?
    private var generation = 0

    init(
        permission: MicrophonePermissionProviding,
        capture: MicrophoneCapturing,
        store: RecordingStoring,
        audioSession: AudioSessionControlling,
        playbackSnapshot: @escaping @MainActor () -> RecordingPlaybackSnapshot
    ) {
        self.permission = permission
        self.capture = capture
        self.store = store
        self.audioSession = audioSession
        self.playbackSnapshot = playbackSnapshot
    }

    func start() async {
        switch state {
        case .stopped, .failed, .interrupted: break
        default: return
        }
        generation += 1
        let startGeneration = generation
        cancelRequested = false
        pendingReason = nil
        capturedSamples = 0
        eventCount = 0

        if permission.status() == .notDetermined {
            state = .requestingPermission
            let granted = await permission.request()
            guard !cancelRequested, generation == startGeneration else {
                state = .stopped
                return
            }
            guard granted else {
                state = .failed("麦克风权限未开启，请到系统设置中允许极简睡眠使用麦克风")
                return
            }
        } else if permission.status() != .granted {
            state = .failed("麦克风权限未开启，请到系统设置中允许极简睡眠使用麦克风")
            return
        }

        state = .starting
        let id = UUID()
        var sessionActivated = false
        do {
            _ = try await store.startSession(
                id: id, at: Date(), timeZoneIdentifier: TimeZone.current.identifier
            )
            if cancelRequested || generation != startGeneration {
                try? await store.deleteSession(id: id)
                state = .stopped
                return
            }
            currentSessionID = id
            try audioSession.setRecordingActive(true)
            sessionActivated = true
            let frames = try capture.makeFrames()
            let pipeline = RecordingPipeline(
                sessionID: id,
                store: store,
                onProgress: { [weak self] samples, count in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == startGeneration else { return }
                        self.capturedSamples = samples
                        self.eventCount = count
                    }
                }
            )
            self.pipeline = pipeline
            state = .recording
            consumeTask = Task { [weak self] in
                await self?.runFrames(frames, pipeline: pipeline, generation: startGeneration)
            }
        } catch {
            capture.stop()
            if sessionActivated { try? audioSession.setRecordingActive(false) }
            if currentSessionID == id {
                try? await store.deleteSession(id: id)
                currentSessionID = nil
            }
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        switch state {
        case .requestingPermission, .starting:
            cancelRequested = true
            state = .stopped
        case .recording:
            state = .stopping
            capture.stop()
            await consumeTask?.value
        case .stopping:
            await consumeTask?.value
        default:
            return
        }
    }

    func handleSafetyEvent(_ event: AudioSafetyEvent) async {
        switch state {
        case .requestingPermission, .starting:
            cancelRequested = true
            state = .interrupted(Self.safetyReason(event))
        case .recording:
            pendingReason = Self.safetyReason(event)
            state = .stopping
            capture.stop()
            await consumeTask?.value
        case .stopping:
            if pendingReason == nil { pendingReason = Self.safetyReason(event) }
            await consumeTask?.value
        default:
            return
        }
    }

    private func runFrames(
        _ frames: AsyncThrowingStream<[Int16], Error>,
        pipeline: RecordingPipeline,
        generation: Int
    ) async {
        var streamError: Error?
        do {
            for try await frame in frames {
                try await pipeline.consume(frame, playback: playbackSnapshot())
            }
        } catch {
            streamError = error
        }
        capture.stop()
        let reason = streamError?.localizedDescription
            ?? pendingReason
            ?? (state == .stopping ? nil : "麦克风采集意外结束")
        let status: RecordingSessionStatus = reason == nil ? .completed : .interrupted
        do {
            try await pipeline.finish(status: status, reason: reason)
        } catch {
            if streamError == nil { streamError = error }
        }
        try? audioSession.setRecordingActive(false)
        self.pipeline = nil
        consumeTask = nil
        currentSessionID = nil
        guard self.generation == generation else { return }
        if let streamError {
            state = .failed(streamError.localizedDescription)
        } else if let reason {
            state = .interrupted(reason)
        } else {
            state = .stopped
        }
    }

    private static func safetyReason(_ event: AudioSafetyEvent) -> String {
        switch event {
        case .interruptionBegan: return "系统音频中断，夜间记录已停止"
        case .oldDeviceUnavailable: return "耳机或音频设备断开，夜间记录已停止"
        }
    }
}
