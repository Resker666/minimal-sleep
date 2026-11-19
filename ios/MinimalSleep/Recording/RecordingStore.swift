import Darwin
import Foundation

enum RecordingStoreLimits {
    static let maximumTotalBytes: Int64 = 1_024 * 1_024 * 1_024
    static let minimumAvailableBytes: Int64 = 200 * 1_024 * 1_024
}

enum RecordingStoreError: Error, Equatable, LocalizedError, Sendable {
    case totalSizeExceeded
    case insufficientFreeSpace
    case missingSession
    case missingEvent
    case sessionNotRecording
    case duplicateSession
    case corruptSession(UUID)
    case unsupportedSchemaVersion(Int)
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .totalSizeExceeded: return "录音已达到 1 GiB 空间上限"
        case .insufficientFreeSpace: return "设备剩余空间不足 200 MiB，已停止记录"
        case .missingSession: return "这次夜间记录不存在"
        case .missingEvent: return "声音片段不存在"
        case .sessionNotRecording: return "这次夜间记录已经结束"
        case .duplicateSession: return "夜间记录编号已存在"
        case let .corruptSession(id): return "夜间记录 \(id.uuidString) 无法读取，原始文件已保留"
        case let .unsupportedSchemaVersion(version): return "不支持的录音数据版本：\(version)"
        case .invalidFileName: return "声音片段文件名无效"
        }
    }
}

struct StagedRecordingFile: Sendable {
    let originalURL: URL
    let stagedURL: URL
}

protocol RecordingFileSystem: Sendable {
    func loadIndex() throws -> Data?
    func saveIndex(_ data: Data) throws
    func sessionIDs() throws -> [UUID]
    func loadSession(id: UUID) throws -> Data?
    func saveSession(id: UUID, data: Data) throws
    func publishWAV(sessionID: UUID, eventID: UUID, samples: [Int16], sampleRate: Int) throws -> String
    func removeWAV(sessionID: UUID, fileName: String) throws
    func stageWAVDeletion(sessionID: UUID, fileName: String) throws -> StagedRecordingFile
    func restoreWAVDeletion(_ staged: StagedRecordingFile) throws
    func discardStagedWAV(_ staged: StagedRecordingFile) throws
    func recoverTemporaryFiles(sessionID: UUID, committedFileNames: Set<String>) throws
    func removeSessionDirectory(id: UUID) throws
    func eventFileURL(sessionID: UUID, fileName: String) -> URL
    func totalRecordingBytes() throws -> Int64
    func availableCapacity() throws -> Int64
}

protocol RecordingStoring: Sendable {
    func startSession(id: UUID, at: Date, timeZoneIdentifier: String) async throws -> RecordingSession
    func appendSegment(
        _ segment: RecordingAudioSegment,
        to sessionID: UUID,
        playbackAffected: Bool,
        createdAt: Date
    ) async throws -> RecordingEvent
    func replacePlaybackIntervals(
        _ intervals: [RecordingPlaybackInterval],
        capturedSamples: Int64,
        for sessionID: UUID
    ) async throws
    func finishSession(
        id: UUID,
        at date: Date,
        status: RecordingSessionStatus,
        reason: String?,
        capturedSamples: Int64,
        playbackIntervals: [RecordingPlaybackInterval]
    ) async throws
    func deleteSession(id: UUID) async throws
}

actor RecordingStore {
    private let fileSystem: RecordingFileSystem
    private let makeID: @Sendable () -> UUID
    private var cachedSessions: [UUID: RecordingSession]?

    init(fileSystem: RecordingFileSystem, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.fileSystem = fileSystem
        self.makeID = makeID
    }

    func sessions() throws -> [RecordingSessionSummary] {
        try loadIfNeeded()
        return summaries(from: cachedSessions ?? [:])
    }

    func session(id: UUID) throws -> RecordingSession {
        try loadIfNeeded()
        guard let session = cachedSessions?[id] else { throw RecordingStoreError.missingSession }
        return session
    }

    func startSession(id: UUID, at: Date, timeZoneIdentifier: String) throws -> RecordingSession {
        try loadIfNeeded()
        try checkCapacity(adding: 0)
        guard cachedSessions?[id] == nil else { throw RecordingStoreError.duplicateSession }
        let session = RecordingSession(id: id, startedAt: at, timeZoneIdentifier: timeZoneIdentifier)
        do {
            try fileSystem.saveSession(id: id, data: JSONEncoder.recording.encode(session))
        } catch {
            // This ID has not been published in the index and cannot contain user audio.
            // Remove a directory left by a partial metadata write before the next launch.
            try? fileSystem.removeSessionDirectory(id: id)
            throw error
        }
        cachedSessions?[id] = session
        try saveIndex()
        return session
    }

    func appendSegment(
        _ segment: RecordingAudioSegment,
        to sessionID: UUID,
        playbackAffected: Bool,
        createdAt: Date
    ) throws -> RecordingEvent {
        try loadIfNeeded()
        guard var session = cachedSessions?[sessionID] else { throw RecordingStoreError.missingSession }
        guard session.status == .recording else { throw RecordingStoreError.sessionNotRecording }
        guard !segment.samples.isEmpty else { throw PCM16WAVWriterError.emptySamples }
        try checkCapacity(adding: Int64(segment.samples.count) * 2 + 44)

        let id = makeID()
        let fileName = try fileSystem.publishWAV(
            sessionID: sessionID, eventID: id, samples: segment.samples, sampleRate: 16_000
        )
        let event = RecordingEvent(
            id: id,
            sessionID: sessionID,
            groupID: segment.groupID,
            startSample: segment.startSample,
            sampleCount: Int64(segment.samples.count),
            fileName: fileName,
            playbackAffected: playbackAffected,
            createdAt: createdAt
        )
        session.events.append(event)
        do {
            try fileSystem.saveSession(id: sessionID, data: JSONEncoder.recording.encode(session))
        } catch {
            try? fileSystem.removeWAV(sessionID: sessionID, fileName: fileName)
            throw error
        }
        cachedSessions?[sessionID] = session
        try saveIndex()
        return event
    }

    func replacePlaybackIntervals(
        _ intervals: [RecordingPlaybackInterval],
        capturedSamples: Int64,
        for sessionID: UUID
    ) throws {
        try loadIfNeeded()
        guard var session = cachedSessions?[sessionID] else { throw RecordingStoreError.missingSession }
        guard session.status == .recording else { throw RecordingStoreError.sessionNotRecording }
        session.playbackIntervals = intervals
        session.capturedSamples = capturedSamples
        try fileSystem.saveSession(id: sessionID, data: JSONEncoder.recording.encode(session))
        cachedSessions?[sessionID] = session
        try saveIndex()
    }

    func finishSession(
        id: UUID,
        at date: Date,
        status: RecordingSessionStatus,
        reason: String?,
        capturedSamples: Int64,
        playbackIntervals: [RecordingPlaybackInterval]
    ) throws {
        try loadIfNeeded()
        guard var session = cachedSessions?[id] else { throw RecordingStoreError.missingSession }
        guard session.status == .recording else { throw RecordingStoreError.sessionNotRecording }
        session.endedAt = date
        session.status = status
        session.endReason = reason
        session.capturedSamples = capturedSamples
        session.playbackIntervals = playbackIntervals
        try fileSystem.saveSession(id: id, data: JSONEncoder.recording.encode(session))
        cachedSessions?[id] = session
        try saveIndex()
    }

    func eventFileURL(sessionID: UUID, eventID: UUID) throws -> URL {
        let session = try self.session(id: sessionID)
        guard let event = session.events.first(where: { $0.id == eventID }) else {
            throw RecordingStoreError.missingEvent
        }
        guard Self.isSafeFileName(event.fileName, eventID: event.id) else {
            throw RecordingStoreError.invalidFileName
        }
        return fileSystem.eventFileURL(sessionID: sessionID, fileName: event.fileName)
    }

    func deleteEvent(sessionID: UUID, eventID: UUID) throws {
        try loadIfNeeded()
        guard let oldSession = cachedSessions?[sessionID] else { throw RecordingStoreError.missingSession }
        guard let event = oldSession.events.first(where: { $0.id == eventID }) else {
            throw RecordingStoreError.missingEvent
        }
        guard Self.isSafeFileName(event.fileName, eventID: event.id) else {
            throw RecordingStoreError.invalidFileName
        }
        let staged = try fileSystem.stageWAVDeletion(sessionID: sessionID, fileName: event.fileName)
        var updated = oldSession
        updated.events.removeAll { $0.id == eventID }
        do {
            try fileSystem.saveSession(id: sessionID, data: JSONEncoder.recording.encode(updated))
            cachedSessions?[sessionID] = updated
            try saveIndex()
            try fileSystem.discardStagedWAV(staged)
        } catch {
            try? fileSystem.saveSession(id: sessionID, data: JSONEncoder.recording.encode(oldSession))
            cachedSessions?[sessionID] = oldSession
            try? saveIndex()
            try? fileSystem.restoreWAVDeletion(staged)
            throw error
        }
    }

    func deleteSession(id: UUID) throws {
        try loadIfNeeded()
        guard cachedSessions?[id] != nil else { throw RecordingStoreError.missingSession }
        try fileSystem.removeSessionDirectory(id: id)
        cachedSessions?.removeValue(forKey: id)
        try saveIndex()
    }

    private func loadIfNeeded() throws {
        guard cachedSessions == nil else { return }
        let storedIndex: RecordingIndex?
        if let data = try fileSystem.loadIndex() {
            do {
                storedIndex = try JSONDecoder.recording.decode(RecordingIndex.self, from: data)
            } catch {
                storedIndex = nil
            }
            if let storedIndex, storedIndex.schemaVersion != 1 {
                throw RecordingStoreError.unsupportedSchemaVersion(storedIndex.schemaVersion)
            }
        } else {
            storedIndex = nil
        }

        var recovered: [UUID: RecordingSession] = [:]
        for id in try fileSystem.sessionIDs() {
            guard let data = try fileSystem.loadSession(id: id),
                  var session = try? JSONDecoder.recording.decode(RecordingSession.self, from: data) else {
                throw RecordingStoreError.corruptSession(id)
            }
            guard session.schemaVersion == 1 else {
                throw RecordingStoreError.unsupportedSchemaVersion(session.schemaVersion)
            }
            guard session.id == id,
                  session.events.allSatisfy({ Self.isSafeFileName($0.fileName, eventID: $0.id) }) else {
                throw RecordingStoreError.corruptSession(id)
            }
            try fileSystem.recoverTemporaryFiles(
                sessionID: id,
                committedFileNames: Set(session.events.map(\.fileName))
            )
            if session.status == .recording {
                session.status = .interrupted
                session.endedAt = Date()
                session.endReason = "App 意外退出"
                try fileSystem.saveSession(id: id, data: JSONEncoder.recording.encode(session))
            }
            recovered[id] = session
        }
        let rebuilt = RecordingIndex(sessions: summaries(from: recovered))
        if storedIndex != rebuilt {
            try fileSystem.saveIndex(JSONEncoder.recording.encode(rebuilt))
        }
        cachedSessions = recovered
    }

    private func checkCapacity(adding bytes: Int64) throws {
        let total = try fileSystem.totalRecordingBytes()
        guard total < RecordingStoreLimits.maximumTotalBytes,
              bytes <= RecordingStoreLimits.maximumTotalBytes - total else {
            throw RecordingStoreError.totalSizeExceeded
        }
        let available = try fileSystem.availableCapacity()
        guard available >= RecordingStoreLimits.minimumAvailableBytes,
              bytes <= available - RecordingStoreLimits.minimumAvailableBytes else {
            throw RecordingStoreError.insufficientFreeSpace
        }
    }

    private func saveIndex() throws {
        let index = RecordingIndex(sessions: summaries(from: cachedSessions ?? [:]))
        try fileSystem.saveIndex(JSONEncoder.recording.encode(index))
    }

    private func summaries(from sessions: [UUID: RecordingSession]) -> [RecordingSessionSummary] {
        sessions.values.map(RecordingSessionSummary.init(session:)).sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func isSafeFileName(_ name: String, eventID: UUID) -> Bool {
        name == "\(eventID.uuidString.lowercased()).wav"
    }
}

extension RecordingStore: RecordingStoring { }

struct FileManagerRecordingFileSystem: RecordingFileSystem {
    private let rootURL: URL
    private let writer: PCM16WAVWriting
    private var files: FileManager { .default }

    static func applicationSupport() throws -> FileManagerRecordingFileSystem {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return try FileManagerRecordingFileSystem(
            rootURL: applicationSupport.appendingPathComponent("NightRecordings", isDirectory: true)
        )
    }

    init(rootURL: URL, writer: PCM16WAVWriting = PCM16WAVWriter()) throws {
        self.rootURL = rootURL
        self.writer = writer
        try files.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        var protectedRoot = rootURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)
        try files.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: rootURL.path
        )
    }

    func loadIndex() throws -> Data? { try load(indexURL) }
    func saveIndex(_ data: Data) throws { try save(data, to: indexURL) }

    func sessionIDs() throws -> [UUID] {
        try files.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
    }

    func loadSession(id: UUID) throws -> Data? { try load(sessionURL(id: id)) }

    func saveSession(id: UUID, data: Data) throws {
        let directory = sessionDirectory(id: id)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try save(data, to: sessionURL(id: id))
    }

    func publishWAV(sessionID: UUID, eventID: UUID, samples: [Int16], sampleRate: Int) throws -> String {
        let name = "\(eventID.uuidString.lowercased()).wav"
        let final = eventFileURL(sessionID: sessionID, fileName: name)
        let temporary = final.appendingPathExtension("part")
        try writer.write(samples: samples, sampleRate: sampleRate, temporaryURL: temporary, finalURL: final)
        return name
    }

    func removeWAV(sessionID: UUID, fileName: String) throws {
        try files.removeItem(at: eventFileURL(sessionID: sessionID, fileName: fileName))
    }

    func stageWAVDeletion(sessionID: UUID, fileName: String) throws -> StagedRecordingFile {
        let original = eventFileURL(sessionID: sessionID, fileName: fileName)
        let staged = original.appendingPathExtension("deleting")
        try files.moveItem(at: original, to: staged)
        return StagedRecordingFile(originalURL: original, stagedURL: staged)
    }

    func restoreWAVDeletion(_ staged: StagedRecordingFile) throws {
        try files.moveItem(at: staged.stagedURL, to: staged.originalURL)
    }

    func discardStagedWAV(_ staged: StagedRecordingFile) throws {
        try files.removeItem(at: staged.stagedURL)
    }

    func recoverTemporaryFiles(sessionID: UUID, committedFileNames: Set<String>) throws {
        let directory = sessionDirectory(id: sessionID)
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            if name.hasSuffix(".wav.part") {
                let stem = String(name.dropLast(".wav.part".count))
                guard UUID(uuidString: stem) != nil else {
                    throw RecordingStoreError.corruptSession(sessionID)
                }
                try files.removeItem(at: url)
            } else if name.hasSuffix(".wav.deleting") {
                let originalName = String(name.dropLast(".deleting".count))
                let stem = String(originalName.dropLast(".wav".count))
                guard UUID(uuidString: stem) != nil else {
                    throw RecordingStoreError.corruptSession(sessionID)
                }
                let original = eventFileURL(sessionID: sessionID, fileName: originalName)
                if committedFileNames.contains(originalName) {
                    guard !files.fileExists(atPath: original.path) else {
                        throw RecordingStoreError.corruptSession(sessionID)
                    }
                    try files.moveItem(at: url, to: original)
                } else {
                    // The metadata may have been changed just before a crash. Keep the WAV
                    // until a person can decide whether the deletion really committed.
                    throw RecordingStoreError.corruptSession(sessionID)
                }
            } else if name.hasPrefix(".session.json.") && name.hasSuffix(".part") {
                let middle = String(name.dropFirst(".session.json.".count).dropLast(".part".count))
                guard UUID(uuidString: middle) != nil else {
                    throw RecordingStoreError.corruptSession(sessionID)
                }
                try files.removeItem(at: url)
            }
        }
    }

    func removeSessionDirectory(id: UUID) throws {
        try files.removeItem(at: sessionDirectory(id: id))
    }

    func eventFileURL(sessionID: UUID, fileName: String) -> URL {
        sessionDirectory(id: sessionID).appendingPathComponent(fileName, isDirectory: false)
    }

    func totalRecordingBytes() throws -> Int64 {
        guard let enumerator = files.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }

    func availableCapacity() throws -> Int64 {
        let attributes = try files.attributesOfFileSystem(forPath: rootURL.path)
        return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    private var sessionsURL: URL { rootURL.appendingPathComponent("Sessions", isDirectory: true) }
    private var indexURL: URL { rootURL.appendingPathComponent("index.json", isDirectory: false) }

    private func sessionDirectory(id: UUID) -> URL {
        sessionsURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func sessionURL(id: UUID) -> URL {
        sessionDirectory(id: id).appendingPathComponent("session.json", isDirectory: false)
    }

    private func load(_ url: URL) throws -> Data? {
        guard files.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func save(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).part"
        )
        try data.write(to: temporary, options: .withoutOverwriting)
        defer { try? files.removeItem(at: temporary) }
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
