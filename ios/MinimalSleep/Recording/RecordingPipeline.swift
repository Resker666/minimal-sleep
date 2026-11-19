import Foundation

enum RecordingPipelineError: LocalizedError {
    case stopped

    var errorDescription: String? { "夜间记录已经停止处理音频" }
}

actor RecordingPipeline {
    private struct OpenPlaybackInterval {
        let id: UUID
        let soundID: String
        let appVolume: Float
        let startSample: Int64
    }

    private let sessionID: UUID
    private let store: RecordingStoring
    private let sampleRate: Int
    private let onProgress: @Sendable (Int64, Int) -> Void
    private var detector = EnergyDetector()
    private var segmenter: EventSegmenter
    private var sampleCursor: Int64 = 0
    private var lastProgressSample: Int64 = 0
    private var lastCheckpointSample: Int64 = 0
    private var eventCount = 0
    private var intervals: [RecordingPlaybackInterval] = []
    private var openPlayback: OpenPlaybackInterval?
    private var failed = false
    private var finished = false

    init(
        sessionID: UUID,
        store: RecordingStoring,
        sampleRate: Int = 16_000,
        preSeconds: Int = 3,
        postSeconds: Int = 3,
        maxSeconds: Int = 60,
        onProgress: @escaping @Sendable (Int64, Int) -> Void = { _, _ in }
    ) {
        self.sessionID = sessionID
        self.store = store
        self.sampleRate = sampleRate
        self.segmenter = EventSegmenter(
            sampleRate: sampleRate,
            preSeconds: preSeconds,
            postSeconds: postSeconds,
            maxSeconds: maxSeconds
        )
        self.onProgress = onProgress
    }

    func consume(_ samples: [Int16], playback: RecordingPlaybackSnapshot) async throws {
        guard !failed && !finished else { throw RecordingPipelineError.stopped }
        guard !samples.isEmpty else { return }
        observePlayback(playback)
        let isCandidate = detector.isCandidate(samples)
        let segments = segmenter.push(samples: samples, isCandidate: isCandidate)
        sampleCursor += Int64(samples.count)
        for segment in segments {
            try await save(segment)
        }
        if sampleCursor - lastCheckpointSample >= Int64(sampleRate) * 60 {
            try await checkpoint()
        }
        if sampleCursor - lastProgressSample >= Int64(sampleRate) {
            lastProgressSample = sampleCursor
            onProgress(sampleCursor, eventCount)
        }
    }

    func finish(status: RecordingSessionStatus, reason: String?) async throws {
        guard !finished else { return }
        finished = true
        var flushError: Error?
        if !failed {
            for segment in segmenter.finish() {
                do {
                    try await save(segment)
                } catch {
                    flushError = error
                    break
                }
            }
        }
        closePlayback(at: sampleCursor)
        let finalStatus: RecordingSessionStatus = flushError == nil ? status : .interrupted
        try await store.finishSession(
            id: sessionID,
            at: Date(),
            status: finalStatus,
            reason: flushError?.localizedDescription ?? reason,
            capturedSamples: sampleCursor,
            playbackIntervals: intervals
        )
        onProgress(sampleCursor, eventCount)
        if let flushError { throw flushError }
    }

    private func observePlayback(_ snapshot: RecordingPlaybackSnapshot) {
        if let openPlayback,
           snapshot.isPlaying,
           openPlayback.soundID == snapshot.soundID,
           openPlayback.appVolume == snapshot.appVolume {
            return
        }
        closePlayback(at: sampleCursor)
        if snapshot.isPlaying {
            openPlayback = OpenPlaybackInterval(
                id: UUID(),
                soundID: snapshot.soundID,
                appVolume: snapshot.appVolume,
                startSample: sampleCursor
            )
        }
    }

    private func closePlayback(at endSample: Int64) {
        guard let openPlayback else { return }
        if endSample > openPlayback.startSample {
            intervals.append(RecordingPlaybackInterval(
                id: openPlayback.id,
                sessionID: sessionID,
                soundID: openPlayback.soundID,
                appVolume: openPlayback.appVolume,
                startSample: openPlayback.startSample,
                endSample: endSample
            ))
        }
        self.openPlayback = nil
    }

    private func save(_ segment: RecordingAudioSegment) async throws {
        let segmentEnd = segment.startSample + Int64(segment.samples.count)
        let overlapsClosed = intervals.contains {
            $0.startSample < segmentEnd && $0.endSample > segment.startSample
        }
        let overlapsOpen = openPlayback.map {
            $0.startSample < segmentEnd && sampleCursor > segment.startSample
        } ?? false
        do {
            _ = try await store.appendSegment(
                segment,
                to: sessionID,
                playbackAffected: overlapsClosed || overlapsOpen,
                createdAt: Date()
            )
            try await checkpoint()
        } catch {
            failed = true
            throw error
        }
        eventCount += 1
        onProgress(sampleCursor, eventCount)
    }

    private func checkpoint() async throws {
        var currentIntervals = intervals
        if let openPlayback, sampleCursor > openPlayback.startSample {
            currentIntervals.append(RecordingPlaybackInterval(
                id: openPlayback.id,
                sessionID: sessionID,
                soundID: openPlayback.soundID,
                appVolume: openPlayback.appVolume,
                startSample: openPlayback.startSample,
                endSample: sampleCursor
            ))
        }
        do {
            try await store.replacePlaybackIntervals(
                currentIntervals, capturedSamples: sampleCursor, for: sessionID
            )
            lastCheckpointSample = sampleCursor
        } catch {
            failed = true
            throw error
        }
    }
}
