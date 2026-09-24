import Foundation
import XCTest
@testable import MinimalSleep

final class RecordingPipelineTests: XCTestCase {
    func testPlaybackOverlapMarksOnlyOverlappingSegment() async throws {
        let store = FakeRecordingStoring()
        let pipeline = RecordingPipeline(sessionID: UUID(), store: store, sampleRate: 10)
        try await pipeline.consume(quiet(30), playback: snapshot(false))
        try await pipeline.consume(loud(10), playback: snapshot(true))
        try await pipeline.consume(quiet(30), playback: snapshot(true))
        try await pipeline.consume(quiet(30), playback: snapshot(false))
        try await pipeline.consume(loud(10), playback: snapshot(false))
        try await pipeline.consume(quiet(30), playback: snapshot(false))
        try await pipeline.finish(status: .completed, reason: nil)

        let events = await store.events
        XCTAssertEqual(events.map(\.affected), [true, false])
        XCTAssertEqual(events.map { $0.segment.samples.count }, [70, 70])
    }

    func testPlaybackSwitchClosesOldIntervalAtCurrentSampleCursor() async throws {
        let store = FakeRecordingStoring()
        let pipeline = RecordingPipeline(sessionID: UUID(), store: store, sampleRate: 10)
        try await pipeline.consume(quiet(10), playback: snapshot(true, soundID: "rain"))
        try await pipeline.consume(quiet(10), playback: snapshot(true, soundID: "ocean"))
        try await pipeline.consume(quiet(10), playback: snapshot(false))
        try await pipeline.finish(status: .completed, reason: nil)

        let intervals = await store.finalIntervals
        XCTAssertEqual(intervals.map(\.soundID), ["rain", "ocean"])
        XCTAssertEqual(intervals.map(\.startSample), [0, 10])
        XCTAssertEqual(intervals.map(\.endSample), [10, 20])
    }

    func testFinishFlushesSegmentAndClosesOpenPlaybackInterval() async throws {
        let store = FakeRecordingStoring()
        let pipeline = RecordingPipeline(sessionID: UUID(), store: store, sampleRate: 10)
        try await pipeline.consume(loud(10), playback: snapshot(true))
        try await pipeline.finish(status: .completed, reason: nil)

        let events = await store.events
        let intervals = await store.finalIntervals
        let sampleCount = await store.finalCapturedSamples
        XCTAssertEqual(events.map { $0.segment.samples.count }, [10])
        XCTAssertEqual(intervals.map(\.endSample), [10])
        XCTAssertEqual(sampleCount, 10)
    }

    func testStoreFailureStopsFurtherConsumption() async throws {
        let store = FakeRecordingStoring()
        await store.failAppend()
        let pipeline = RecordingPipeline(sessionID: UUID(), store: store, sampleRate: 10, maxSeconds: 1)

        do {
            try await pipeline.consume(loud(10), playback: snapshot(false))
            XCTFail("The injected append failure should surface")
        } catch { }
        do {
            try await pipeline.consume(loud(10), playback: snapshot(false))
            XCTFail("A failed pipeline must not keep consuming")
        } catch { }
        let attempts = await store.appendAttempts
        XCTAssertEqual(attempts, 1)
    }

    private func quiet(_ count: Int) -> [Int16] { Array(repeating: 0, count: count) }
    private func loud(_ count: Int) -> [Int16] { Array(repeating: 8_000, count: count) }
    private func snapshot(_ playing: Bool, soundID: String = "rain") -> RecordingPlaybackSnapshot {
        RecordingPlaybackSnapshot(isPlaying: playing, soundID: soundID, appVolume: 0.5)
    }
}

private actor FakeRecordingStoring: RecordingStoring {
    struct SavedEvent: Sendable {
        let segment: RecordingAudioSegment
        let affected: Bool
    }

    private(set) var events: [SavedEvent] = []
    private(set) var finalIntervals: [RecordingPlaybackInterval] = []
    private(set) var finalCapturedSamples: Int64 = 0
    private(set) var appendAttempts = 0
    private var shouldFailAppend = false

    func failAppend() { shouldFailAppend = true }

    func startSession(id: UUID, at: Date, timeZoneIdentifier: String) throws -> RecordingSession {
        RecordingSession(id: id, startedAt: at, timeZoneIdentifier: timeZoneIdentifier)
    }

    func appendSegment(
        _ segment: RecordingAudioSegment, to sessionID: UUID,
        playbackAffected: Bool, createdAt: Date
    ) throws -> RecordingEvent {
        appendAttempts += 1
        if shouldFailAppend { throw RecordingStoreError.insufficientFreeSpace }
        events.append(SavedEvent(segment: segment, affected: playbackAffected))
        return RecordingEvent(
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
    ) throws {
        finalIntervals = playbackIntervals
        finalCapturedSamples = capturedSamples
    }
    func deleteSession(id: UUID) throws { }
}
