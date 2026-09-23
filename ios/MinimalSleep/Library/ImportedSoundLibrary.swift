import Combine
import Foundation

@MainActor
final class ImportedSoundLibrary: ObservableObject {
    @Published private(set) var sounds: [ImportedSound] = []
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    var isAvailable: Bool { store != nil && fileSystem != nil }

    private let store: ImportedSoundStore?
    private let fileSystem: FileManagerImportedSoundFileSystem?

    init(playbackController: ImportedPlaybackControlling) {
        do {
            let fileSystem = try FileManagerImportedSoundFileSystem.applicationSupport()
            self.fileSystem = fileSystem
            self.store = ImportedSoundStore(
                fileSystem: fileSystem,
                capacityProvider: FileSystemCapacityProvider(directory: fileSystem.directory),
                audioValidator: AVFoundationImportedAudioValidator(),
                playbackController: playbackController
            )
            reload()
        } catch {
            self.fileSystem = nil
            self.store = nil
            self.errorMessage = Self.message(for: error)
        }
    }

    func reload() {
        guard let store else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                sounds = try await store.allSounds()
                errorMessage = nil
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    func importSound(from url: URL) {
        guard let store else { return }
        isBusy = true
        errorMessage = nil
        let displayName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        Task {
            defer { isBusy = false }
            do {
                _ = try await store.importSound(
                    from: url,
                    displayName: displayName,
                    fileExtension: fileExtension
                )
                sounds = try await store.allSounds()
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    func delete(id: UUID) {
        guard let store else { return }
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await store.delete(id: id)
                sounds = try await store.allSounds()
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    func fileURL(for sound: ImportedSound) -> URL? {
        fileSystem?.directory.appendingPathComponent(sound.storedFileName, isDirectory: false)
    }

    func reportFileImporterError(_ error: Error) {
        errorMessage = Self.message(for: error)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "操作失败，请重试"
    }
}
