import XCTest
@testable import MinimalSleep

final class RecordingModelsTests: XCTestCase {
    func testSessionRoundTripsWithSchemaVersionOne() throws {
        let session = RecordingSession.fixture(status: .completed)
        let data = try JSONEncoder.recording.encode(session)
        let decoded = try JSONDecoder.recording.decode(RecordingSession.self, from: data)
        XCTAssertEqual(decoded, session)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.eventCount, 1)
    }

    func testDatesAreStoredAsISO8601Text() throws {
        let data = try JSONEncoder.recording.encode(RecordingSession.fixture(status: .completed))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("2026-09-24T12:00:00Z"))
    }
}

private extension RecordingSession {
    static func fixture(status: RecordingSessionStatus) -> RecordingSession {
        let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let start = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        return RecordingSession(
            id: sessionID,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            timeZoneIdentifier: "Asia/Shanghai",
            capturedSamples: 960_000,
            status: status,
            endReason: nil,
            events: [RecordingEvent(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                sessionID: sessionID,
                groupID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                startSample: 16_000,
                sampleCount: 32_000,
                fileName: "22222222-2222-2222-2222-222222222222.wav",
                playbackAffected: true,
                createdAt: start
            )],
            playbackIntervals: [RecordingPlaybackInterval(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                sessionID: sessionID,
                soundID: "white-noise",
                appVolume: 0.5,
                startSample: 0,
                endSample: 48_000
            )]
        )
    }
}
