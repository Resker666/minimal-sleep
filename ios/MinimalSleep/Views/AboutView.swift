import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("隐私") {
                    Text("首版仅做离线助眠播放，不申请麦克风权限。应用不主动上传数据，也不包含分析 SDK。导入音频保存在 App 私有目录。")
                }

                Section("内置资源") {
                    Text("大雨剪辑、雨雷剪辑：录制与授权 Resker666，CC BY 4.0；已完成循环剪辑，iOS 工程使用无损 PCM 派生资源。")
                    Text("合成大雨、合成海浪：本仓库脚本生成的程序近似音，不是真实天气或海岸录音。")
                    Text("白噪声：本仓库脚本以固定种子生成。")
                }
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
