import SwiftUI

@MainActor
struct RootTabView: View {
    @ObservedObject var audioCoordinator: AudioCoordinator
    @ObservedObject var importedLibrary: ImportedSoundLibrary
    @ObservedObject var recordingCoordinator: NightRecordingCoordinator
    @ObservedObject var recordingLibrary: RecordingLibrary

    var body: some View {
        TabView {
            HomeView(
                coordinator: audioCoordinator,
                importedLibrary: importedLibrary,
                recordingCoordinator: recordingCoordinator
            )
            .tabItem { Label("今晚", systemImage: "moon.stars") }

            RecordingHistoryView(
                library: recordingLibrary,
                coordinator: recordingCoordinator
            )
            .tabItem { Label("记录", systemImage: "waveform") }
        }
    }
}
