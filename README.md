# minimal-sleep-ios

极简睡眠 iOS：免费、开源、离线的助眠应用。使用 Swift、SwiftUI 与系统音频框架，在 Mac 上通过 Xcode 开发，支持 iOS 17 及以上的 iPhone/iPad。

本仓库从 [minimal-sleep](https://github.com/Resker666/minimal-sleep) 分离，独立保存源码、构建配置、音频源素材和测试。构建不需要 Android 仓库、Gradle 或 Android SDK。Android 继续在原仓库维护。

## 功能与分支

`main` 保留原主干的播放预览版：五种内置声音、循环播放、后台音频、锁屏播放/暂停、15/30/60/90 分钟或整晚、结束前 10 秒淡出、音量/定时偏好，以及 MP3/M4A/WAV 私有导入。

`codex/ios-night-recording` 单独保留尚未合入原主干的夜间录音开发工作，包含麦克风采集、声音片段、记录列表、回听与删除。拆分本身不会将该功能合入 `main`。进度见 [iOS 进度](docs/ios-progress.md)，测试范围见 [iOS 验证记录](docs/ios-validation.md)。

两条分支均为开发预览；历史模拟器测试结果不能证明当前拆分版已通过真机或整夜验收。不提供睡眠评分、深睡或呼吸暂停结论。

## 从独立仓库构建

需要完整 Xcode 及 iOS 平台组件、Python 3.12、FFmpeg/FFprobe。现有可复现音频清单基于 Homebrew FFmpeg **9.0.2**；其他版本可能产生不同哈希，CI 会拒绝清单差异，不能直接放宽校验。

从仓库根目录先准备音频，再打开工程：

```bash
python3 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
python3 tools/prepare_ios_audio.py --ffmpeg "$(command -v ffmpeg)" --ffprobe "$(command -v ffprobe)"
git diff --exit-code -- assets-manifest.csv ios/MinimalSleep/Resources/audio-derivations.json
open ios/MinimalSleep.xcodeproj
```

三段 WAV 已纳入 Git；两段雨声由本仓库 `assets/source-audio/` 中的 Ogg 生成 M4A。生成文件不纳入 Git，脚本拒绝覆盖已有输出。详见 [资源说明](docs/assets.md)。

无签名模拟器构建：

```bash
xcodebuild -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/minimal-sleep-ios-derived build CODE_SIGNING_ALLOWED=NO
```

测试前用 `xcrun simctl list devices available` 选择当前 Mac 上可用的 iPhone 模拟器，然后按 [开发说明](docs/ios-development.md) 执行 XCTest。真机安装需要自己的 Apple ID 与 Personal Team；保持 Bundle ID `io.github.resker666.minimalsleep`，不要为试装而卸载含有私有音频的旧 App。

## CI、隐私和许可证

[iOS 工作流](.github/workflows/ios-build.yml) 准备音频、校验清单、执行 XCTest 并构建模拟器 App。Artifact 是未签名模拟器包，不能直接安装到 iPhone。两端分别维护版本与发布，不自动同步功能。

应用离线运行，导入音频留在 App 私有目录；录音分支同样不上传原音。Git 中不保存录音、账号凭据、签名证书、Team ID 或构建产物。

源码与合成 WAV 为 [Apache-2.0](LICENSE)；两段录制雨声及派生 M4A 为 Resker666 / CC BY 4.0。详见 [第三方说明](THIRD_PARTY_NOTICES.md)、[资源清单](assets-manifest.csv) 和 [拆分记录](docs/repository-split.md)。
