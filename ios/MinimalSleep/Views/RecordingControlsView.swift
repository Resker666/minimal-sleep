import SwiftUI

@MainActor
struct RecordingControlsView: View {
    @ObservedObject var coordinator: NightRecordingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle")
                Text(statusText)
                Spacer()
                Text(durationText)
                    .monospacedDigit()
            }
            .font(.subheadline)

            Text("已保存 \(coordinator.eventCount) 个声音片段")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: action) {
                Label(buttonTitle, systemImage: buttonIcon)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.state == .stopping)
            .accessibilityLabel(buttonTitle)

            Text("录音只保存在本机。播放助眠声音可能被麦克风录入；受影响片段会标记。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonTitle: String {
        switch coordinator.state {
        case .requestingPermission, .starting: return "取消夜间记录"
        case .recording: return "结束夜间记录"
        case .stopping: return "正在保存"
        default: return "开始夜间记录"
        }
    }

    private var buttonIcon: String {
        switch coordinator.state {
        case .recording, .requestingPermission, .starting, .stopping: return "stop.fill"
        default: return "record.circle"
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .stopped: return "已停止"
        case .requestingPermission: return "等待麦克风授权"
        case .starting: return "准备中"
        case .recording: return "记录中"
        case .stopping: return "正在保存"
        case let .interrupted(reason): return reason
        case let .failed(message): return message
        }
    }

    private var durationText: String {
        let seconds = Int(coordinator.capturedSamples / 16_000)
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    private func action() {
        Task {
            switch coordinator.state {
            case .recording, .requestingPermission, .starting:
                await coordinator.stop()
            case .stopping:
                break
            default:
                await coordinator.start()
            }
        }
    }
}
