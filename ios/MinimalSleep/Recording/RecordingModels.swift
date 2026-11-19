import Foundation

enum RecordingSessionStatus: String, Codable, Sendable {
    case recording
    case completed
    case interrupted
}

struct RecordingEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let groupID: UUID
    let startSample: Int64
    let sampleCount: Int64
    let fileName: String
    let playbackAffected: Bool
    let createdAt: Date
}

struct RecordingPlaybackInterval: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let soundID: String
    let appVolume: Float
    let startSample: Int64
    let endSample: Int64
}

struct RecordingSession: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let timeZoneIdentifier: String
    var capturedSamples: Int64
    var status: RecordingSessionStatus
    var endReason: String?
    var events: [RecordingEvent]
    var playbackIntervals: [RecordingPlaybackInterval]

    var eventCount: Int { events.count }

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        timeZoneIdentifier: String,
        capturedSamples: Int64 = 0,
        status: RecordingSessionStatus = .recording,
        endReason: String? = nil,
        events: [RecordingEvent] = [],
        playbackIntervals: [RecordingPlaybackInterval] = []
    ) {
        schemaVersion = 1
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.capturedSamples = capturedSamples
        self.status = status
        self.endReason = endReason
        self.events = events
        self.playbackIntervals = playbackIntervals
    }
}

struct RecordingSessionSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let capturedSamples: Int64
    let status: RecordingSessionStatus
    let eventCount: Int

    init(session: RecordingSession) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        capturedSamples = session.capturedSamples
        status = session.status
        eventCount = session.eventCount
    }
}

struct RecordingIndex: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var sessions: [RecordingSessionSummary]

    init(sessions: [RecordingSessionSummary] = []) {
        schemaVersion = 1
        self.sessions = sessions
    }
}

extension JSONEncoder {
    static var recording: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var recording: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
