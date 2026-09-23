import Foundation
import XCTest
@testable import MinimalSleep

@MainActor
final class ImportedSoundStoreTests: XCTestCase {
    private let sourceURL = URL(fileURLWithPath: "/fake/source.wav")

    func testConcurrentImportsStopAtTenAndEleventhIsRejected() async throws {
        let fileSystem = FakeImportedSoundFileSystem(byteCounts: Array(repeating: 1, count: 11))
        let ids = UUIDSequence()
        let store = makeStore(fileSystem: fileSystem, ids: ids)
        let inputURL = sourceURL

        let successful = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<11 {
                group.addTask {
                    do {
                        _ = try await store.importSound(
                            from: inputURL,
                            displayName: "sound-\(index)",
                            fileExtension: "wav"
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await result in group where result { count += 1 }
            return count
        }

        XCTAssertEqual(successful, ImportedSoundLimits.maximumCount)
        let storedSounds = try await store.allSounds()
        XCTAssertEqual(storedSounds.count, ImportedSoundLimits.maximumCount)
        XCTAssertEqual(fileSystem.stageCallCount, ImportedSoundLimits.maximumCount)
    }

    func testOneHundredMiBBoundaryIsAcceptedAndOneByteOverIsRejected() async throws {
        let acceptedFS = FakeImportedSoundFileSystem(byteCounts: [ImportedSoundLimits.maximumFileBytes])
        let acceptedStore = makeStore(fileSystem: acceptedFS)
        let accepted = try await acceptedStore.importSound(
            from: sourceURL,
            displayName: "limit.wav",
            fileExtension: "wav"
        )
        XCTAssertEqual(accepted.byteCount, ImportedSoundLimits.maximumFileBytes)

        let rejectedFS = FakeImportedSoundFileSystem(byteCounts: [ImportedSoundLimits.maximumFileBytes + 1])
        let rejectedStore = makeStore(fileSystem: rejectedFS)
        await assertImportError(.fileTooLarge, from: rejectedStore)
    }

    func testThreeHundredMiBTotalBoundaryIsInclusive() async throws {
        let existingBytes = 200 * Int64(1024 * 1024)
        let acceptedFS = FakeImportedSoundFileSystem(
            byteCounts: [100 * Int64(1024 * 1024)],
            committedBytes: existingBytes
        )
        let acceptedStore = makeStore(fileSystem: acceptedFS)
        _ = try await acceptedStore.importSound(
            from: sourceURL,
            displayName: "accepted.wav",
            fileExtension: "wav"
        )

        let rejectedFS = FakeImportedSoundFileSystem(
            byteCounts: [100 * Int64(1024 * 1024)],
            committedBytes: existingBytes + 1
        )
        let rejectedStore = makeStore(fileSystem: rejectedFS)
        await assertImportError(.totalSizeExceeded, from: rejectedStore)
    }

    func testTwoHundredMiBRemainingBoundaryIsInclusive() async throws {
        let exactCapacity = FakeCapacityProvider(
            availableBytes: ImportedSoundLimits.minimumAvailableBytesAfterCopy
        )
        let acceptedStore = makeStore(
            fileSystem: FakeImportedSoundFileSystem(byteCounts: [1]),
            capacity: exactCapacity
        )
        _ = try await acceptedStore.importSound(
            from: sourceURL,
            displayName: "accepted.wav",
            fileExtension: "wav"
        )

        let lowCapacity = FakeCapacityProvider(
            availableBytes: ImportedSoundLimits.minimumAvailableBytesAfterCopy - 1
        )
        let rejectedStore = makeStore(
            fileSystem: FakeImportedSoundFileSystem(byteCounts: [1]),
            capacity: lowCapacity
        )
        await assertImportError(.insufficientFreeSpace, from: rejectedStore)
    }

    func testSameDisplayNameUsesDifferentInternalFiles() async throws {
        let fileSystem = FakeImportedSoundFileSystem(byteCounts: [10, 10])
        let store = makeStore(fileSystem: fileSystem, ids: UUIDSequence())

        let first = try await store.importSound(
            from: sourceURL,
            displayName: "rain.wav",
            fileExtension: "wav"
        )
        let second = try await store.importSound(
            from: sourceURL,
            displayName: "rain.wav",
            fileExtension: "wav"
        )

        XCTAssertEqual(first.displayName, second.displayName)
        XCTAssertNotEqual(first.storedFileName, second.storedFileName)
        XCTAssertEqual(fileSystem.committedFileNames.count, 2)
    }

    func testUnsupportedExtensionIsRejectedBeforeCopy() async {
        let fileSystem = FakeImportedSoundFileSystem(byteCounts: [10])
        let store = makeStore(fileSystem: fileSystem)

        do {
            _ = try await store.importSound(
                from: sourceURL,
                displayName: "rain.ogg",
                fileExtension: "ogg"
            )
            XCTFail("Expected unsupported extension failure")
        } catch {
            XCTAssertEqual(error as? ImportedSoundStoreError, .invalidFileExtension)
        }
        XCTAssertEqual(fileSystem.stageCallCount, 0)
    }

    func testValidationOrIndexFailureLeavesNoIndexGarbage() async throws {
        let validationFS = FakeImportedSoundFileSystem(byteCounts: [10])
        let validationStore = makeStore(
            fileSystem: validationFS,
            validator: FakeAudioValidator(error: TestFailure.validation)
        )
        do {
            _ = try await validationStore.importSound(
                from: sourceURL,
                displayName: "bad.wav",
                fileExtension: "wav"
            )
            XCTFail("Expected validation failure")
        } catch {
            XCTAssertEqual(error as? TestFailure, .validation)
        }
        let soundsAfterValidationFailure = try await validationStore.allSounds()
        XCTAssertEqual(soundsAfterValidationFailure, [])
        XCTAssertTrue(validationFS.committedFileNames.isEmpty)
        XCTAssertTrue(validationFS.stagedTokens.isEmpty)

        let indexFS = FakeImportedSoundFileSystem(byteCounts: [10])
        indexFS.failNextIndexSave = true
        let indexStore = makeStore(fileSystem: indexFS)
        do {
            _ = try await indexStore.importSound(
                from: sourceURL,
                displayName: "index.wav",
                fileExtension: "wav"
            )
            XCTFail("Expected index failure")
        } catch {
            XCTAssertEqual(error as? TestFailure, .indexWrite)
        }
        let soundsAfterIndexFailure = try await indexStore.allSounds()
        XCTAssertEqual(soundsAfterIndexFailure, [])
        XCTAssertTrue(indexFS.committedFileNames.isEmpty)
    }

    func testDeletingCurrentSoundStopsPlaybackBeforeRemovingFile() async throws {
        let events = EventLog()
        let fileSystem = FakeImportedSoundFileSystem(byteCounts: [10], events: events)
        let playback = FakePlaybackController(events: events)
        let store = makeStore(fileSystem: fileSystem, playback: playback)
        let sound = try await store.importSound(
            from: sourceURL,
            displayName: "current.wav",
            fileExtension: "wav"
        )
        playback.currentID = sound.id
        events.values.removeAll()

        try await store.delete(id: sound.id)

        XCTAssertEqual(events.values, ["stop:\(sound.id)", "remove:\(sound.storedFileName)"])
        let soundsAfterDelete = try await store.allSounds()
        XCTAssertEqual(soundsAfterDelete, [])
    }

    func testPersistedIndexIsReadableByANewStoreInstance() async throws {
        let fileSystem = FakeImportedSoundFileSystem(byteCounts: [10])
        let firstStore = makeStore(fileSystem: fileSystem)
        let imported = try await firstStore.importSound(
            from: sourceURL,
            displayName: "persisted.wav",
            fileExtension: "wav"
        )

        let reopenedStore = makeStore(fileSystem: fileSystem)
        let reopenedSounds = try await reopenedStore.allSounds()

        XCTAssertEqual(reopenedSounds, [imported])
    }

    func testCorruptIndexIsRebuiltFromCommittedUUIDFiles() async throws {
        let recoveredID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let storedName = "\(recoveredID.uuidString.lowercased()).wav"
        let fileSystem = FakeImportedSoundFileSystem(
            byteCounts: [],
            committedFiles: [storedName: 42]
        )
        fileSystem.indexData = Data("{not-json".utf8)
        let store = makeStore(fileSystem: fileSystem)

        let recovered = try await store.allSounds()

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].id, recoveredID)
        XCTAssertEqual(recovered[0].storedFileName, storedName)
        XCTAssertEqual(recovered[0].byteCount, 42)
        XCTAssertNoThrow(try JSONDecoder().decode([ImportedSound].self, from: XCTUnwrap(fileSystem.indexData)))
    }

    func testFileManagerByteCountExcludesExtensionPreservingStagedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileSystem = try FileManagerImportedSoundFileSystem(directory: directory)
        try Data(repeating: 1, count: 7).write(
            to: directory.appendingPathComponent("00000000-0000-0000-0000-000000000001.wav")
        )
        try Data(repeating: 2, count: 9).write(
            to: directory.appendingPathComponent("00000000-0000-0000-0000-000000000002.part.wav")
        )

        XCTAssertEqual(try fileSystem.totalCommittedBytes(), 7)
    }

    private func makeStore(
        fileSystem: FakeImportedSoundFileSystem,
        capacity: FakeCapacityProvider = FakeCapacityProvider(availableBytes: Int64.max),
        validator: FakeAudioValidator = FakeAudioValidator(),
        playback: FakePlaybackController? = nil,
        ids: UUIDSequence = UUIDSequence()
    ) -> ImportedSoundStore {
        ImportedSoundStore(
            fileSystem: fileSystem,
            capacityProvider: capacity,
            audioValidator: validator,
            playbackController: playback ?? FakePlaybackController(),
            makeID: { ids.next() }
        )
    }

    private func assertImportError(
        _ expected: ImportedSoundStoreError,
        from store: ImportedSoundStore
    ) async {
        do {
            _ = try await store.importSound(
                from: sourceURL,
                displayName: "boundary.wav",
                fileExtension: "wav"
            )
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? ImportedSoundStoreError, expected)
        }
    }
}

private enum TestFailure: Error, Equatable, Sendable {
    case validation
    case indexWrite
}

private final class UUIDSequence: @unchecked Sendable {
    private var value: UInt64 = 1

    func next() -> UUID {
        defer { value += 1 }
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llu", value))!
    }
}

private final class EventLog: @unchecked Sendable {
    var values: [String] = []
}

private final class FakeImportedSoundFileSystem: ImportedSoundFileSystem, @unchecked Sendable {
    var indexData: Data?
    var failNextIndexSave = false
    private var byteCounts: [Int64]
    private var committed: [String: Int64] = [:]
    private var extraCommittedBytes: Int64
    private let events: EventLog?
    private(set) var staged: [String: Int64] = [:]
    private(set) var stageCallCount = 0

    var committedFileNames: Set<String> { Set(committed.keys) }
    var stagedTokens: Set<String> { Set(staged.keys) }

    init(
        byteCounts: [Int64],
        committedBytes: Int64 = 0,
        committedFiles: [String: Int64] = [:],
        events: EventLog? = nil
    ) {
        self.byteCounts = byteCounts
        self.extraCommittedBytes = committedBytes
        self.committed = committedFiles
        self.events = events
    }

    func loadIndex() throws -> Data? { indexData }

    func saveIndex(_ data: Data) throws {
        if failNextIndexSave {
            failNextIndexSave = false
            throw TestFailure.indexWrite
        }
        indexData = data
    }

    func recoverSoundsFromCommittedFiles() throws -> [ImportedSound] {
        committed.keys.sorted().enumerated().compactMap { offset, storedFileName in
            let fileURL = URL(fileURLWithPath: storedFileName)
            guard ImportedSoundLimits.supportedFileExtensions.contains(
                fileURL.pathExtension.lowercased()
            ), let id = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) else {
                return nil
            }
            return ImportedSound(
                id: id,
                displayName: "已恢复音频 \(offset + 1)",
                storedFileName: storedFileName,
                byteCount: committed[storedFileName] ?? 0
            )
        }
    }

    func totalCommittedBytes() throws -> Int64 {
        extraCommittedBytes + committed.values.reduce(0, +)
    }

    func stageCopy(
        from sourceURL: URL,
        stagedFileName: String,
        maximumBytes: Int64
    ) throws -> StagedImportedFile {
        stageCallCount += 1
        let bytes = byteCounts.removeFirst()
        if bytes > maximumBytes { throw ImportedSoundStoreError.fileTooLarge }
        staged[stagedFileName] = bytes
        return StagedImportedFile(
            token: stagedFileName,
            fileURL: URL(fileURLWithPath: "/fake/staged/\(stagedFileName)"),
            byteCount: bytes
        )
    }

    func commit(_ stagedFile: StagedImportedFile, as storedFileName: String) throws {
        guard committed[storedFileName] == nil else {
            throw ImportedSoundStoreError.destinationAlreadyExists
        }
        staged.removeValue(forKey: stagedFile.token)
        committed[storedFileName] = stagedFile.byteCount
    }

    func discard(_ stagedFile: StagedImportedFile) {
        staged.removeValue(forKey: stagedFile.token)
    }

    func removeCommittedFile(named storedFileName: String) throws {
        events?.values.append("remove:\(storedFileName)")
        committed.removeValue(forKey: storedFileName)
    }
}

private struct FakeCapacityProvider: AvailableCapacityProviding {
    let availableBytes: Int64
    func availableCapacityAfterStaging() throws -> Int64 { availableBytes }
}

private struct FakeAudioValidator: ImportedAudioValidating {
    let error: TestFailure?
    init(error: TestFailure? = nil) { self.error = error }
    func validateAudio(stagedFile: StagedImportedFile) throws {
        if let error { throw error }
    }
}

@MainActor
private final class FakePlaybackController: ImportedPlaybackControlling {
    var currentID: UUID?
    private let events: EventLog?
    init(events: EventLog? = nil) { self.events = events }
    func stopIfPlayingImportedSound(id: UUID) {
        guard currentID == id else { return }
        events?.values.append("stop:\(id)")
        currentID = nil
    }
}
