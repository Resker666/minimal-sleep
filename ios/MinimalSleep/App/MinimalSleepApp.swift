import SwiftUI

@main
@MainActor
struct MinimalSleepApp: App {
    @StateObject private var audioCoordinator: AudioCoordinator
    @StateObject private var importedLibrary: ImportedSoundLibrary

    init() {
        let sessionController = AudioSessionController()
        let coordinator = AudioCoordinator(
            engine: AVAudioPlayerPlaybackEngine(sessionController: sessionController),
            preferences: UserDefaultsPlaybackPreferences()
        )
        _audioCoordinator = StateObject(wrappedValue: coordinator)
        _importedLibrary = StateObject(
            wrappedValue: ImportedSoundLibrary(playbackController: coordinator)
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                coordinator: audioCoordinator,
                importedLibrary: importedLibrary
            )
            .preferredColorScheme(.dark)
        }
    }
}
