import SwiftUI

@main
@MainActor
struct MinimalSleepApp: App {
    @StateObject private var audioCoordinator = AudioCoordinator()

    var body: some Scene {
        WindowGroup {
            HomeView(
                coordinator: audioCoordinator,
                importedSounds: [],
                onImport: nil,
                onDelete: nil
            )
            .preferredColorScheme(.dark)
        }
    }
}

// TODO（需 Mac 编译）: In Xcode, inject the AVFoundation AudioPlaybackEngine,
// ImportedAudioValidating, application-support store, and observable import model.
// The nil callbacks keep unfinished import/playback integration visibly unavailable.
