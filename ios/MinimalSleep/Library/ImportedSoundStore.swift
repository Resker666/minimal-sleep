import Foundation

enum ImportedSoundLimits {
    static let maximumCount = 10
    static let maximumFileBytes: Int64 = 100 * 1024 * 1024
    static let maximumTotalBytes: Int64 = 300 * 1024 * 1024
    static let minimumAvailableBytesAfterCopy: Int64 = 200 * 1024 * 1024
    static let supportedFileExtensions: Set<String> = ["mp3", "m4a", "wav"]
}

struct ImportedSound: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let storedFileName: String
    let byteCount: Int64
}

struct StagedImportedFile: Equatable, Sendable {
    let token: String
    let fileURL: URL
    let byteCount: Int64
}

enum ImportedSoundStoreError: Error, Equatable, LocalizedError, Sendable {
    case maximumCountReached
    case emptyFile
    case fileTooLarge
    case totalSizeExceeded
    case insufficientFreeSpace
    case invalidFileExtension
    case destinationAlreadyExists

    var errorDescription: String? {
        switch self {
        case .maximumCountReached:
            return "最多保留 10 个导入声音"
        case .emptyFile:
            return "音频文件为空"
        case .fileTooLarge:
            return "单个音频超过 100 MiB"
        case .totalSizeExceeded:
            return "导入音频总量超过 300 MiB"
        case .insufficientFreeSpace:
            return "复制后设备剩余空间不足 200 MiB"
        case .invalidFileExtension:
            return "无法识别音频扩展名"
        case .destinationAlreadyExists:
            return "内部文件名冲突，请重试"
        }
    }
}

protocol ImportedSoundFileSystem: Sendable {
    func loadIndex() throws -> Data?
    func saveIndex(_ data: Data) throws
    func totalCommittedBytes() throws -> Int64
    func stageCopy(from sourceURL: URL, stagedFileName: String, maximumBytes: Int64) throws -> StagedImportedFile
    func commit(_ staged: StagedImportedFile, as storedFileName: String) throws
    func discard(_ staged: StagedImportedFile)
    func removeCommittedFile(named storedFileName: String) throws
}

protocol AvailableCapacityProviding: Sendable {
    func availableCapacityAfterStaging() throws -> Int64
}

protocol ImportedAudioValidating: Sendable {
    func validateAudio(stagedFile: StagedImportedFile) throws
}

protocol ImportedPlaybackControlling: Sendable {
    func isCurrentImportedSound(id: UUID) -> Bool
    func stopBeforeDeletingImportedSound(id: UUID)
}

actor ImportedSoundStore {
    private let fileSystem: ImportedSoundFileSystem
    private let capacityProvider: AvailableCapacityProviding
    private let audioValidator: ImportedAudioValidating
    private let playbackController: ImportedPlaybackControlling
    private let makeID: @Sendable () -> UUID
    private var cachedSounds: [ImportedSound]?

    init(
        fileSystem: ImportedSoundFileSystem,
        capacityProvider: AvailableCapacityProviding,
        audioValidator: ImportedAudioValidating,
        playbackController: ImportedPlaybackControlling,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.fileSystem = fileSystem
        self.capacityProvider = capacityProvider
        self.audioValidator = audioValidator
        self.playbackController = playbackController
        self.makeID = makeID
    }

    func allSounds() throws -> [ImportedSound] {
        try loadSoundsIfNeeded()
    }

    func importSound(
        from sourceURL: URL,
        displayName: String,
        fileExtension: String
    ) throws -> ImportedSound {
        let existing = try loadSoundsIfNeeded()
        guard existing.count < ImportedSoundLimits.maximumCount else {
            throw ImportedSoundStoreError.maximumCountReached
        }

        let normalizedExtension = try Self.normalizedExtension(fileExtension)
        let id = makeID()
        let storedFileName = "\(id.uuidString.lowercased()).\(normalizedExtension)"
        let staged = try fileSystem.stageCopy(
            from: sourceURL,
            stagedFileName: "\(storedFileName).part",
            maximumBytes: ImportedSoundLimits.maximumFileBytes
        )
        var committed = false

        do {
            guard staged.byteCount > 0 else { throw ImportedSoundStoreError.emptyFile }
            guard staged.byteCount <= ImportedSoundLimits.maximumFileBytes else {
                throw ImportedSoundStoreError.fileTooLarge
            }
            let committedBytes = try fileSystem.totalCommittedBytes()
            guard committedBytes <= ImportedSoundLimits.maximumTotalBytes - staged.byteCount else {
                throw ImportedSoundStoreError.totalSizeExceeded
            }
            guard try capacityProvider.availableCapacityAfterStaging()
                >= ImportedSoundLimits.minimumAvailableBytesAfterCopy else {
                throw ImportedSoundStoreError.insufficientFreeSpace
            }

            try audioValidator.validateAudio(stagedFile: staged)
            try fileSystem.commit(staged, as: storedFileName)
            committed = true

            let trimmedName = String(displayName.prefix(60))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sound = ImportedSound(
                id: id,
                displayName: trimmedName.isEmpty ? "导入声音" : trimmedName,
                storedFileName: storedFileName,
                byteCount: staged.byteCount
            )
            let updated = existing + [sound]
            do {
                try persist(updated)
            } catch {
                try? fileSystem.removeCommittedFile(named: storedFileName)
                throw error
            }
            cachedSounds = updated
            return sound
        } catch {
            if !committed {
                fileSystem.discard(staged)
            }
            throw error
        }
    }

    func delete(id: UUID) throws {
        let existing = try loadSoundsIfNeeded()
        guard let sound = existing.first(where: { $0.id == id }) else { return }

        if playbackController.isCurrentImportedSound(id: id) {
            playbackController.stopBeforeDeletingImportedSound(id: id)
        }

        let updated = existing.filter { $0.id != id }
        try persist(updated)
        do {
            try fileSystem.removeCommittedFile(named: sound.storedFileName)
            cachedSounds = updated
        } catch {
            try? persist(existing)
            throw error
        }
    }

    private func loadSoundsIfNeeded() throws -> [ImportedSound] {
        if let cachedSounds { return cachedSounds }
        guard let data = try fileSystem.loadIndex() else {
            cachedSounds = []
            return []
        }
        let decoded = try JSONDecoder().decode([ImportedSound].self, from: data)
        cachedSounds = decoded
        return decoded
    }

    private func persist(_ sounds: [ImportedSound]) throws {
        try fileSystem.saveIndex(JSONEncoder().encode(sounds))
    }

    private static func normalizedExtension(_ value: String) throws -> String {
        let candidate = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let allowed = candidate.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57)
        }
        guard allowed,
              (1...8).contains(candidate.count),
              ImportedSoundLimits.supportedFileExtensions.contains(candidate) else {
            throw ImportedSoundStoreError.invalidFileExtension
        }
        return candidate
    }
}

final class FileManagerImportedSoundFileSystem: ImportedSoundFileSystem, @unchecked Sendable {
    let directory: URL
    private let fileManager: FileManager
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var resourceDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceDirectory.setResourceValues(values)
    }

    static func applicationSupport(fileManager: FileManager = .default) throws
        -> FileManagerImportedSoundFileSystem {
        guard let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try FileManagerImportedSoundFileSystem(
            directory: root.appendingPathComponent("ImportedSounds", isDirectory: true),
            fileManager: fileManager
        )
    }

    func loadIndex() throws -> Data? {
        guard fileManager.fileExists(atPath: indexURL.path) else { return nil }
        return try Data(contentsOf: indexURL)
    }

    func saveIndex(_ data: Data) throws {
        try data.write(to: indexURL, options: .atomic)
    }

    func totalCommittedBytes() throws -> Int64 {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        )
        .filter { $0.lastPathComponent != indexURL.lastPathComponent && !$0.lastPathComponent.hasSuffix(".part") }
        .reduce(0) { result, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return result + (values.isRegularFile == true ? Int64(values.fileSize ?? 0) : 0)
        }
    }

    func stageCopy(
        from sourceURL: URL,
        stagedFileName: String,
        maximumBytes: Int64
    ) throws -> StagedImportedFile {
        let destination = directory.appendingPathComponent(stagedFileName)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ImportedSoundStoreError.destinationAlreadyExists
        }

        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let input = try FileHandle(forReadingFrom: sourceURL)
            let output = try FileHandle(forWritingTo: destination)
            defer {
                try? input.close()
                try? output.close()
            }

            var byteCount: Int64 = 0
            while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
                byteCount += Int64(data.count)
                guard byteCount <= maximumBytes else {
                    throw ImportedSoundStoreError.fileTooLarge
                }
                try output.write(contentsOf: data)
            }
            try output.synchronize()
            return StagedImportedFile(
                token: stagedFileName,
                fileURL: destination,
                byteCount: byteCount
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func commit(_ staged: StagedImportedFile, as storedFileName: String) throws {
        let source = directory.appendingPathComponent(staged.token)
        let destination = directory.appendingPathComponent(storedFileName)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ImportedSoundStoreError.destinationAlreadyExists
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    func discard(_ staged: StagedImportedFile) {
        try? fileManager.removeItem(at: directory.appendingPathComponent(staged.token))
    }

    func removeCommittedFile(named storedFileName: String) throws {
        let url = directory.appendingPathComponent(storedFileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

struct FileSystemCapacityProvider: AvailableCapacityProviding {
    let directory: URL

    func availableCapacityAfterStaging() throws -> Int64 {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

// TODO（需 Mac 编译）: Implement ImportedAudioValidating with AVFoundation and
// reject undecodable or shorter-than-one-second audio before commit. Wire the
// actor to an async UI model so security-scoped copies never block the main actor.
