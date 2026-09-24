import Foundation
import XCTest
@testable import MinimalSleep

final class RecordingStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinimalSleepRecordingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStartingSessionPersistsMetadataAndListSummary() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let store = RecordingStore(fileSystem: files)
        let id = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!

        let started = try await store.startSession(id: id, at: now, timeZoneIdentifier: "Asia/Shanghai")

        XCTAssertEqual(started.status, .recording)
        XCTAssertEqual(started.eventCount, 0)
        let summaries = try await store.sessions()
        XCTAssertEqual(summaries.map(\.id), [id])
        let sessionData = try XCTUnwrap(files.loadSession(id: id))
        XCTAssertEqual(try JSONDecoder.recording.decode(RecordingSession.self, from: sessionData), started)
        let indexData = try XCTUnwrap(files.loadIndex())
        let index = try JSONDecoder.recording.decode(RecordingIndex.self, from: indexData)
        XCTAssertEqual(index.sessions.map(\.id), [id])
    }

    func testSessionSaveFailureRollsBackPublishedWAVAndDoesNotExposeEvent() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let failing = FaultInjectingRecordingFileSystem(base: files)
        let store = RecordingStore(fileSystem: failing)
        let id = UUID()
        _ = try await store.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        failing.failNext = .saveSession

        do {
            _ = try await store.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
            XCTFail("The injected session write should fail")
        } catch { }

        let stored = try await store.session(id: id)
        XCTAssertTrue(stored.events.isEmpty)
        XCTAssertEqual(try files.sessionIDs(), [id])
        let wavFiles = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Sessions/\(id.uuidString.lowercased())"),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "wav" }
        XCTAssertTrue(wavFiles.isEmpty)
    }

    func testIndexSaveFailureKeepsRecoverableSessionAndWAV() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let failing = FaultInjectingRecordingFileSystem(base: files)
        let store = RecordingStore(fileSystem: failing)
        let id = UUID()
        _ = try await store.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        failing.failNext = .saveIndex

        do {
            _ = try await store.appendSegment(segment(), to: id, playbackAffected: true, createdAt: Date())
            XCTFail("The injected index write should fail")
        } catch { }

        let sessionData = try XCTUnwrap(files.loadSession(id: id))
        let persisted = try JSONDecoder.recording.decode(RecordingSession.self, from: sessionData)
        let event = try XCTUnwrap(persisted.events.first)
        XCTAssertTrue(event.playbackAffected)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: files.eventFileURL(sessionID: id, fileName: event.fileName).path
        ))
        let oldIndex = try JSONDecoder.recording.decode(
            RecordingIndex.self, from: XCTUnwrap(files.loadIndex())
        )
        XCTAssertEqual(oldIndex.sessions.single?.eventCount, 0)
    }

    func testRecoveryRebuildsIndexAfterPreviousIndexSaveFailure() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let failing = FaultInjectingRecordingFileSystem(base: files)
        let id = UUID()
        let first = RecordingStore(fileSystem: failing)
        _ = try await first.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        failing.failNext = .saveIndex
        _ = try? await first.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())

        let recovered = RecordingStore(fileSystem: files)
        let summaries = try await recovered.sessions()
        XCTAssertEqual(summaries.single?.eventCount, 1)
        XCTAssertEqual(summaries.single?.status, .interrupted)
        let index = try JSONDecoder.recording.decode(
            RecordingIndex.self, from: XCTUnwrap(files.loadIndex())
        )
        XCTAssertEqual(index.sessions.single?.eventCount, 1)
    }

    func testCorruptIndexRebuildsFromValidSessionFiles() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let first = RecordingStore(fileSystem: files)
        let id = UUID()
        _ = try await first.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        try files.saveIndex(Data("not JSON".utf8))

        let recovered = RecordingStore(fileSystem: files)
        let summaries = try await recovered.sessions()
        XCTAssertEqual(summaries.map(\.id), [id])
        XCTAssertEqual(summaries.single?.status, .interrupted)
        _ = try JSONDecoder.recording.decode(RecordingIndex.self, from: XCTUnwrap(files.loadIndex()))
    }

    func testStaleRecordingSessionBecomesInterruptedWithoutDeletingWAV() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let first = RecordingStore(fileSystem: files)
        let id = UUID()
        _ = try await first.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        let event = try await first.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())

        let recovered = RecordingStore(fileSystem: files)
        let session = try await recovered.session(id: id)
        XCTAssertEqual(session.status, .interrupted)
        XCTAssertEqual(session.endReason, "App 意外退出")
        XCTAssertEqual(session.events.map(\.id), [event.id])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: files.eventFileURL(sessionID: id, fileName: event.fileName).path
        ))
    }

    func testUnknownSchemaVersionIsReportedWithoutOverwritingFiles() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let data = Data("{\"schemaVersion\":99,\"sessions\":[]}".utf8)
        try files.saveIndex(data)

        let store = RecordingStore(fileSystem: files)
        do {
            _ = try await store.sessions()
            XCTFail("A future schema must not be replaced")
        } catch {
            XCTAssertEqual(error as? RecordingStoreError, .unsupportedSchemaVersion(99))
        }
        XCTAssertEqual(try files.loadIndex(), data)
    }

    func testDeleteEventRestoresMetadataWhenFileRemovalFails() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let failing = FaultInjectingRecordingFileSystem(base: files)
        let store = RecordingStore(fileSystem: failing)
        let id = UUID()
        _ = try await store.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        let event = try await store.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
        failing.failNext = .discardStagedWAV

        do {
            try await store.deleteEvent(sessionID: id, eventID: event.id)
            XCTFail("The injected file removal should fail")
        } catch { }

        let stored = try await store.session(id: id)
        XCTAssertEqual(stored.events.map(\.id), [event.id])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: files.eventFileURL(sessionID: id, fileName: event.fileName).path
        ))
        let index = try JSONDecoder.recording.decode(
            RecordingIndex.self, from: XCTUnwrap(files.loadIndex())
        )
        XCTAssertEqual(index.sessions.single?.eventCount, 1)
    }

    func testDeleteSessionLeavesIndexWhenDirectoryRemovalFails() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let failing = FaultInjectingRecordingFileSystem(base: files)
        let store = RecordingStore(fileSystem: failing)
        let id = UUID()
        _ = try await store.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        failing.failNext = .removeSessionDirectory

        do {
            try await store.deleteSession(id: id)
            XCTFail("The injected directory deletion should fail")
        } catch { }

        let summaries = try await store.sessions()
        XCTAssertEqual(summaries.map(\.id), [id])
        let index = try JSONDecoder.recording.decode(
            RecordingIndex.self, from: XCTUnwrap(files.loadIndex())
        )
        XCTAssertEqual(index.sessions.map(\.id), [id])
    }

    func testRecordingDirectoryIsExcludedFromBackup() throws {
        _ = try FileManagerRecordingFileSystem(rootURL: directory)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testOneGiBLimitRejectsStartAtBoundary() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let limited = FaultInjectingRecordingFileSystem(base: files)
        limited.totalBytesOverride = RecordingStoreLimits.maximumTotalBytes
        let store = RecordingStore(fileSystem: limited)

        do {
            _ = try await store.startSession(id: UUID(), at: Date(), timeZoneIdentifier: "UTC")
            XCTFail("Exactly 1 GiB must be rejected")
        } catch {
            XCTAssertEqual(error as? RecordingStoreError, .totalSizeExceeded)
        }
        XCTAssertTrue(try files.sessionIDs().isEmpty)
    }

    func testBelowTwoHundredMiBRejectsStart() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let limited = FaultInjectingRecordingFileSystem(base: files)
        limited.availableBytesOverride = RecordingStoreLimits.minimumAvailableBytes - 1
        let store = RecordingStore(fileSystem: limited)

        do {
            _ = try await store.startSession(id: UUID(), at: Date(), timeZoneIdentifier: "UTC")
            XCTFail("Below 200 MiB must be rejected")
        } catch {
            XCTAssertEqual(error as? RecordingStoreError, .insufficientFreeSpace)
        }
    }

    func testTwoHundredMiBBoundaryAllowsStartButRejectsNewWAV() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let limited = FaultInjectingRecordingFileSystem(base: files)
        limited.availableBytesOverride = RecordingStoreLimits.minimumAvailableBytes
        let store = RecordingStore(fileSystem: limited)
        let id = UUID()

        _ = try await store.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        do {
            _ = try await store.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
            XCTFail("A new WAV would lower available space below 200 MiB")
        } catch {
            XCTAssertEqual(error as? RecordingStoreError, .insufficientFreeSpace)
        }
        let stored = try await store.session(id: id)
        XCTAssertTrue(stored.events.isEmpty)
    }

    func testSuccessfulDeletionRemovesEventAndThenWholeSession() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let store = RecordingStore(fileSystem: files)
        let id = UUID()
        _ = try await store.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        let event = try await store.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
        let wavURL = files.eventFileURL(sessionID: id, fileName: event.fileName)

        try await store.deleteEvent(sessionID: id, eventID: event.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wavURL.path))
        let remaining = try await store.session(id: id)
        XCTAssertTrue(remaining.events.isEmpty)

        try await store.deleteSession(id: id)
        let summaries = try await store.sessions()
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertTrue(try files.sessionIDs().isEmpty)
    }

    func testRecoveryRestoresStagedWAVReferencedBySession() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let first = RecordingStore(fileSystem: files)
        let id = UUID()
        _ = try await first.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        let event = try await first.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
        let staged = try files.stageWAVDeletion(sessionID: id, fileName: event.fileName)

        let recovered = RecordingStore(fileSystem: files)
        _ = try await recovered.sessions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.stagedURL.path))
    }

    func testRecoveryRemovesAbandonedWAVPartWithoutDeletingCommittedWAV() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let first = RecordingStore(fileSystem: files)
        let id = UUID()
        _ = try await first.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        let event = try await first.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
        let committed = files.eventFileURL(sessionID: id, fileName: event.fileName)
        let abandoned = files.eventFileURL(sessionID: id, fileName: "\(UUID().uuidString.lowercased()).wav.part")
        try Data("partial".utf8).write(to: abandoned)

        let recovered = RecordingStore(fileSystem: files)
        _ = try await recovered.sessions()

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed.path))
    }

    func testRecoveryPreservesAmbiguousStagedWAVWhenMetadataNoLongerListsIt() async throws {
        let files = try FileManagerRecordingFileSystem(rootURL: directory)
        let first = RecordingStore(fileSystem: files)
        let id = UUID()
        _ = try await first.startSession(id: id, at: Date(), timeZoneIdentifier: "UTC")
        let event = try await first.appendSegment(segment(), to: id, playbackAffected: false, createdAt: Date())
        let staged = try files.stageWAVDeletion(sessionID: id, fileName: event.fileName)
        var metadata = try await first.session(id: id)
        metadata.events.removeAll()
        try files.saveSession(id: id, data: JSONEncoder.recording.encode(metadata))

        let recovered = RecordingStore(fileSystem: files)
        do {
            _ = try await recovered.sessions()
            XCTFail("Ambiguous staged recording requires manual recovery")
        } catch {
            XCTAssertEqual(error as? RecordingStoreError, .corruptSession(id))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.stagedURL.path))
    }

    private func segment() -> RecordingAudioSegment {
        RecordingAudioSegment(groupID: UUID(), startSample: 0, samples: Array(repeating: 2_000, count: 320))
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

private final class FaultInjectingRecordingFileSystem: RecordingFileSystem, @unchecked Sendable {
    enum Operation { case saveIndex, saveSession, discardStagedWAV, removeSessionDirectory }
    enum InjectedFailure: Error { case expected }

    let base: RecordingFileSystem
    var failNext: Operation?
    var totalBytesOverride: Int64?
    var availableBytesOverride: Int64?

    init(base: RecordingFileSystem) { self.base = base }

    private func check(_ operation: Operation) throws {
        if failNext == operation {
            failNext = nil
            throw InjectedFailure.expected
        }
    }

    func loadIndex() throws -> Data? { try base.loadIndex() }
    func saveIndex(_ data: Data) throws { try check(.saveIndex); try base.saveIndex(data) }
    func sessionIDs() throws -> [UUID] { try base.sessionIDs() }
    func loadSession(id: UUID) throws -> Data? { try base.loadSession(id: id) }
    func saveSession(id: UUID, data: Data) throws {
        try check(.saveSession)
        try base.saveSession(id: id, data: data)
    }
    func publishWAV(sessionID: UUID, eventID: UUID, samples: [Int16], sampleRate: Int) throws -> String {
        try base.publishWAV(sessionID: sessionID, eventID: eventID, samples: samples, sampleRate: sampleRate)
    }
    func removeWAV(sessionID: UUID, fileName: String) throws {
        try base.removeWAV(sessionID: sessionID, fileName: fileName)
    }
    func stageWAVDeletion(sessionID: UUID, fileName: String) throws -> StagedRecordingFile {
        try base.stageWAVDeletion(sessionID: sessionID, fileName: fileName)
    }
    func restoreWAVDeletion(_ staged: StagedRecordingFile) throws {
        try base.restoreWAVDeletion(staged)
    }
    func discardStagedWAV(_ staged: StagedRecordingFile) throws {
        try check(.discardStagedWAV)
        try base.discardStagedWAV(staged)
    }
    func removeSessionDirectory(id: UUID) throws {
        try check(.removeSessionDirectory)
        try base.removeSessionDirectory(id: id)
    }
    func recoverTemporaryFiles(sessionID: UUID, committedFileNames: Set<String>) throws {
        try base.recoverTemporaryFiles(sessionID: sessionID, committedFileNames: committedFileNames)
    }
    func eventFileURL(sessionID: UUID, fileName: String) -> URL {
        base.eventFileURL(sessionID: sessionID, fileName: fileName)
    }
    func totalRecordingBytes() throws -> Int64 { try totalBytesOverride ?? base.totalRecordingBytes() }
    func availableCapacity() throws -> Int64 { try availableBytesOverride ?? base.availableCapacity() }
}
