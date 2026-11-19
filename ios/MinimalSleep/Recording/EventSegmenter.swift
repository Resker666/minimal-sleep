import Foundation

struct RecordingAudioSegment: Equatable, Sendable {
    let groupID: UUID
    let startSample: Int64
    let samples: [Int16]
}

struct EventSegmenter: Sendable {
    private let preSampleCount: Int
    private let postSampleCount: Int
    private let maximumSampleCount: Int

    private var sampleCursor: Int64 = 0
    private var preBuffer: [Int16] = []
    private var activeSamples: [Int16] = []
    private var activeStartSample: Int64 = 0
    private var activeGroupID: UUID?
    private var quietSampleCount = 0

    init(sampleRate: Int, preSeconds: Int, postSeconds: Int, maxSeconds: Int) {
        precondition(sampleRate > 0 && preSeconds >= 0 && postSeconds >= 0 && maxSeconds > 0)
        preSampleCount = sampleRate * preSeconds
        postSampleCount = sampleRate * postSeconds
        maximumSampleCount = sampleRate * maxSeconds
    }

    mutating func push(samples: [Int16], isCandidate: Bool) -> [RecordingAudioSegment] {
        guard !samples.isEmpty else { return [] }
        let frameStart = sampleCursor
        sampleCursor += Int64(samples.count)

        if activeGroupID == nil {
            guard isCandidate else {
                rememberPreSamples(samples)
                return []
            }
            activeGroupID = UUID()
            activeStartSample = frameStart - Int64(preBuffer.count)
            activeSamples = preBuffer
            preBuffer.removeAll(keepingCapacity: true)
        }

        if isCandidate {
            quietSampleCount = 0
            activeSamples.append(contentsOf: samples)
            return emitFullSegments()
        }

        let needed = max(0, postSampleCount - quietSampleCount)
        let includedCount = min(needed, samples.count)
        if includedCount > 0 {
            activeSamples.append(contentsOf: samples.prefix(includedCount))
            quietSampleCount += includedCount
        }
        rememberPreSamples(samples)
        var result = emitFullSegments()
        if quietSampleCount >= postSampleCount {
            result.append(contentsOf: flushActive())
        }
        return result
    }

    mutating func finish() -> [RecordingAudioSegment] {
        let result = flushActive()
        preBuffer.removeAll(keepingCapacity: false)
        return result
    }

    private mutating func rememberPreSamples(_ samples: [Int16]) {
        guard preSampleCount > 0 else { return }
        preBuffer.append(contentsOf: samples)
        if preBuffer.count > preSampleCount {
            preBuffer.removeFirst(preBuffer.count - preSampleCount)
        }
    }

    private mutating func emitFullSegments() -> [RecordingAudioSegment] {
        guard let groupID = activeGroupID else { return [] }
        var result: [RecordingAudioSegment] = []
        while activeSamples.count >= maximumSampleCount {
            result.append(
                RecordingAudioSegment(
                    groupID: groupID,
                    startSample: activeStartSample,
                    samples: Array(activeSamples.prefix(maximumSampleCount))
                )
            )
            activeSamples.removeFirst(maximumSampleCount)
            activeStartSample += Int64(maximumSampleCount)
        }
        return result
    }

    private mutating func flushActive() -> [RecordingAudioSegment] {
        guard let groupID = activeGroupID else { return [] }
        let result = activeSamples.isEmpty ? [] : [
            RecordingAudioSegment(
                groupID: groupID,
                startSample: activeStartSample,
                samples: activeSamples
            )
        ]
        activeSamples.removeAll(keepingCapacity: false)
        activeGroupID = nil
        quietSampleCount = 0
        return result
    }
}
