import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct HomeView: View {
    @ObservedObject var coordinator: AudioCoordinator
    @ObservedObject var importedLibrary: ImportedSoundLibrary
    @ObservedObject var recordingCoordinator: NightRecordingCoordinator

    @State private var showsAbout = false
    @State private var showsImporter = false

    var body: some View {
        NavigationStack {
            List {
                soundSection
                playbackSection
                timerSection
                Section("夜间记录") {
                    RecordingControlsView(coordinator: recordingCoordinator)
                }
                importSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.055, green: 0.063, blue: 0.067))
            .navigationTitle("极简睡眠")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("隐私与资源说明")
                }
            }
        }
        .tint(Color(red: 0.45, green: 0.76, blue: 0.59))
        .sheet(isPresented: $showsAbout) {
            AboutView()
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    importedLibrary.importSound(from: url)
                }
            case let .failure(error):
                importedLibrary.reportFileImporterError(error)
            }
        }
    }

    private var soundSection: some View {
        Section("声音") {
            ForEach(SoundCatalog.builtIn) { sound in
                Button {
                    coordinator.selectSound(sound)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sound.title)
                                .foregroundStyle(.primary)
                            if let attribution = sound.attribution {
                                Text(attribution)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if sound.isProceduralApproximation {
                                Text("程序近似")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if coordinator.selectedSound.id == sound.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(soundAccessibilityLabel(sound))
            }
        }
    }

    private var playbackSection: some View {
        Section("播放") {
            HStack(spacing: 12) {
                Button {
                    coordinator.isPlaying ? coordinator.pause() : coordinator.play()
                } label: {
                    Label(
                        coordinator.isPlaying ? "暂停" : "播放",
                        systemImage: coordinator.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(coordinator.isPlaying ? "暂停助眠声音" : "播放助眠声音")

                Button {
                    coordinator.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.playbackState == .stopped)
                .accessibilityLabel("停止助眠声音并清除倒计时")
            }

            HStack {
                Image(systemName: "speaker.fill")
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { coordinator.baseVolume },
                        set: { coordinator.setBaseVolume($0) }
                    ),
                    in: 0...1
                )
                    .accessibilityLabel("应用音量")
                    .accessibilityValue("\(Int(coordinator.baseVolume * 100))%")
                Image(systemName: "speaker.wave.3.fill")
                    .accessibilityHidden(true)
            }

            if case let .failed(message) = coordinator.playbackState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var timerSection: some View {
        Section("关闭时间") {
            Picker("关闭时间", selection: durationBinding) {
                ForEach(SleepDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            }

            if let remaining = coordinator.timerSnapshot.remaining,
               coordinator.timerSnapshot.isArmed {
                Text(remainingText(remaining))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("剩余时间 \(remainingText(remaining))")
            }
        }
    }

    private var importSection: some View {
        Section("本地音频") {
            Button {
                showsImporter = true
            } label: {
                Label("导入音频", systemImage: "square.and.arrow.down")
            }
            .disabled(!importedLibrary.isAvailable || importedLibrary.isBusy)
            .accessibilityLabel("从文件导入音频")

            ForEach(importedLibrary.sounds) { sound in
                HStack {
                    Button {
                        if let url = importedLibrary.fileURL(for: sound) {
                            coordinator.selectImportedSound(sound, fileURL: url)
                        }
                    } label: {
                        HStack {
                            Text(sound.displayName)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            if coordinator.currentImportedSoundID == sound.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择 \(sound.displayName)")

                    Spacer()
                    Button(role: .destructive) {
                        importedLibrary.delete(id: sound.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(importedLibrary.isBusy)
                    .accessibilityLabel("删除 \(sound.displayName)")
                }
            }

            if importedLibrary.isBusy {
                ProgressView()
                    .accessibilityLabel("正在处理音频")
            }

            if let message = importedLibrary.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var durationBinding: Binding<SleepDuration> {
        Binding(
            get: { coordinator.selectedDuration },
            set: { coordinator.selectDuration($0) }
        )
    }

    private func soundAccessibilityLabel(_ sound: SoundDescriptor) -> String {
        if let attribution = sound.attribution {
            return "\(sound.title)，录制雨声，\(attribution)"
        }
        if sound.isProceduralApproximation {
            return "\(sound.title)，程序近似音"
        }
        return sound.title
    }

    private func remainingText(_ remaining: TimeInterval) -> String {
        let totalSeconds = Int(ceil(remaining))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
