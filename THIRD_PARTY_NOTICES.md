# 来源与许可证

本项目原创 Swift、Python 源码及三段合成 WAV 继承原项目 [Apache-2.0](LICENSE) 许可证。拆分没有改变音频字节或原作者署名。

两段 `assets/source-audio/rain-01.ogg`、`rain-04.ogg` 及生成的 AAC/M4A 按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 提供，署名 **Resker666**。录制者于 2026-09-22 确认拥有对应音轨权利并授权修改、公开分发。原剪辑各取第 600–900 秒，尾首交叉淡化 2 秒并转码 Ogg；第二段另降低至 0.75 倍增益。iOS 派生步骤仅将 Ogg 转码为 128 kbps AAC/M4A，不再次裁剪、调整增益或重采样。来源、哈希与处理记录见 [资源说明](docs/assets.md)、[资源清单](assets-manifest.csv) 和 [派生清单](ios/MinimalSleep/Resources/audio-derivations.json)。

SwiftUI、AVFoundation、MediaPlayer、Foundation 和 XCTest 由 Apple SDK 提供。FFmpeg/FFprobe 与 Python 为开发时音频工具，不嵌入 iOS App；使用者遵守各自分发包的许可证。iOS 当前树不分发 AndroidX、Room、Media3、LiteRT 或 YAMNet 模型。

用户自行导入的音频与麦克风录音只保存在 App 私有目录，不随源码或 App 分发。原单仓库中的历史提交及其许可证保持可追溯，见 [拆分记录](docs/repository-split.md)。
