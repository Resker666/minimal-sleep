import SwiftUI

@MainActor
struct RecordingHistoryView: View {
    @ObservedObject var library: RecordingLibrary
    @ObservedObject var coordinator: NightRecordingCoordinator
    @State private var sessionToDelete: UUID?

    var body: some View {
        NavigationStack {
            List {
                if library.sessions.isEmpty && !library.isBusy {
                    ContentUnavailableView("尚无记录", systemImage: "waveform")
                }
                ForEach(library.sessions) { summary in
                    NavigationLink {
                        RecordingSessionDetailView(
                            sessionID: summary.id,
                            library: library,
                            coordinator: coordinator
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.startedAt, format: .dateTime.year().month().day().hour().minute())
                            Text("\(summary.eventCount) 个片段 · \(duration(summary.capturedSamples)) · \(status(summary.status))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { sessionToDelete = summary.id }
                            .disabled(recordingIsActive)
                    }
                }
                if let errorMessage = library.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("夜间记录")
            .task { await library.reload() }
            .refreshable { await library.reload() }
            .confirmationDialog("删除整次夜间记录及其所有片段？", isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            )) {
                Button("删除整次记录", role: .destructive) {
                    guard let id = sessionToDelete else { return }
                    sessionToDelete = nil
                    Task { try? await library.deleteSession(id: id) }
                }
            }
        }
    }

    private var recordingIsActive: Bool {
        switch coordinator.state {
        case .requestingPermission, .starting, .recording, .stopping: return true
        default: return false
        }
    }
}

@MainActor
private struct RecordingSessionDetailView: View {
    let sessionID: UUID
    @ObservedObject var library: RecordingLibrary
    @ObservedObject var coordinator: NightRecordingCoordinator
    @State private var eventToDelete: UUID?

    var body: some View {
        List {
            if let session = library.selectedSession, session.id == sessionID {
                Section("本次记录") {
                    Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    Text("有效采集 \(duration(session.capturedSamples)) · \(status(session.status))")
                }

                Section("声音片段") {
                    if session.events.isEmpty {
                        Text("没有保存的片段；这不能证明整晚安静")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.events) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(duration(event.startSample)) 开始 · \(duration(event.sampleCount))")
                            if event.playbackAffected {
                                Text("播放声音期间，片段可能受影响")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            HStack {
                                Button(library.playingEventID == event.id ? "停止回听" : "回听") {
                                    if library.playingEventID == event.id {
                                        library.stopPlayback()
                                    } else {
                                        Task { try? await library.play(sessionID: sessionID, eventID: event.id) }
                                    }
                                }
                                .disabled(recordingIsActive)
                                Spacer()
                                Button("删除片段", role: .destructive) { eventToDelete = event.id }
                                    .disabled(recordingIsActive)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                ProgressView("正在读取记录")
            }
            if let errorMessage = library.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("记录详情")
        .task(id: sessionID) { await library.selectSession(id: sessionID) }
        .onDisappear { library.stopPlayback() }
        .confirmationDialog("删除这个声音片段？", isPresented: Binding(
            get: { eventToDelete != nil },
            set: { if !$0 { eventToDelete = nil } }
        )) {
            Button("删除片段", role: .destructive) {
                guard let id = eventToDelete else { return }
                eventToDelete = nil
                Task { try? await library.deleteEvent(sessionID: sessionID, eventID: id) }
            }
        }
    }

    private var recordingIsActive: Bool {
        switch coordinator.state {
        case .requestingPermission, .starting, .recording, .stopping: return true
        default: return false
        }
    }
}

private func duration(_ samples: Int64) -> String {
    let seconds = Int(samples / 16_000)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

private func status(_ value: RecordingSessionStatus) -> String {
    switch value {
    case .recording: return "记录中"
    case .completed: return "已完成"
    case .interrupted: return "异常中断"
    }
}
