import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "版本 \(version) (\(build)) · 开发预览"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("隐私") {
                    Text("只有你主动开始夜间记录后，应用才会使用麦克风；仅把声音触发片段保存在本机。应用不主动上传录音，也不包含分析 SDK。")
                    Text("助眠声播放可能进入麦克风，重叠片段会标记为可能受影响；目前没有回声消除或声音分类。")
                    Text("普通删除不等于闪存安全擦除。导入音频和夜间记录都保存在 App 私有目录。")
                }

                Section("内置资源") {
                    Text("大雨剪辑、雨雷剪辑：录制与授权 Resker666，CC BY 4.0；iOS 工程使用 AAC/M4A 派生资源。")
                    Text("合成大雨、合成海浪：本仓库脚本生成的程序近似音，不是真实天气或海岸录音。")
                    Text("白噪声：本仓库脚本以固定种子生成。")
                }

                Section("版本") {
                    Text(versionText)
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
