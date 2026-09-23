# iOS progress

当前任务：首轮 iOS 可自用播放版，完成 Mac 上可自动执行的工程、实现、资源和验证工作。

起始提交 / 当前分支：`4d8abbb` / `codex/ios-mvp`。开始实现前将本地 `main` 合入，合并提交为 `b37aba5`。

本轮已完成：

- 建立可直接打开的 `ios/MinimalSleep.xcodeproj` 与共享 `MinimalSleep` scheme；iOS 17.0，Bundle ID `io.github.resker666.minimalsleep`，只启用后台 audio，不声明麦克风用途。
- 接入唯一 `AVAudioPlayer`、`.playback` 音频会话、无限循环、基础音量、切换音轨、来电/中断和耳机断开暂停；首版不自动恢复。
- 接入 MPNowPlayingInfoCenter 和 MPRemoteCommandCenter；锁屏只发布标题、署名和播放状态，不伪造循环音轨时长。
- 使用绝对单调截止时间和 DispatchSourceTimer 更新倒计时；支持 15/30/60/90 分钟与整晚、最后 10 秒线性淡出、暂停不延长、停止清除、改时长重计、旧回调失效、过期远程命令拒绝。
- 完成本地 MP3/M4A/WAV 导入：安全作用域复制、AVAudioFile 解码读取、至少 1 秒、临时文件、UUID 内部名、原子索引、备份排除、10 个/100 MiB/300 MiB/剩余 200 MiB 限制、持久读取、选择播放和删除当前曲目前停止。
- 完成导入和播放故障恢复：完整解码导入文件、临时文件不计入已提交容量、损坏/缺失索引从 UUID 音频文件重建、提交失败清理孤立文件、运行时解码失败停止播放并清除计时器；暂停时切换声音会继续维护原截止时间。
- 使用 UserDefaults 保存关闭时间和基础音量；冷启动不自动播放。
- 用 FFmpeg 从两段已完成循环剪辑的 Ogg 生成 298 秒、44.1 kHz、双声道、16-bit PCM WAV；写入源/输出 SHA-256 和完整派生命令。五段 WAV 都已进入模拟器和设备 App 包。
- 模拟器安装并启动成功，首屏实际渲染正常。自动化没有替代真机听感、锁屏和整夜验证。

构建与测试（2026-09-23 实际结果）：

- `/opt/homebrew/bin/python3.12 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v`：退出码 0，4/4 通过。
- `/opt/homebrew/bin/python3.12 tools/prepare_ios_audio.py --ffmpeg /opt/homebrew/bin/ffmpeg`：退出码 0，生成两段雨声和派生清单。
- 全部 Python 工具测试：14 项中 10 项通过、4 项失败；失败均来自 Homebrew FFmpeg 缺少 `libvorbis` 编码器，错误为 `Unknown encoder 'libvorbis'`。iOS 转码只使用 Vorbis 解码和 `pcm_s16le` 编码，已成功。
- iPhone 18 Pro / iOS 27.0 模拟器 XCTest：退出码 0，31/31 通过，0 跳过。
- 通用 iOS Simulator Debug 无签名构建：退出码 0。
- 通用 iOS device arm64 Debug 无签名构建：退出码 0。
- 两个构建产物均核对到 5 个 WAV；Info.plist 核对到 `UIBackgroundModes = audio`，无 `NSMicrophoneUsageDescription`。
- `xcrun simctl install` 与 `launch`：退出码 0；首屏截图确认声音列表、播放、音量与关闭时间正常渲染。

真机已验证：无。连接的 iPhone `朱颜辞镜花辞树` 当前被 `devicectl` 列为 `unavailable`，且仓库没有 Development Team 或签名凭据。

真机未验证：实际发声、两段雨声各跨至少两次完整循环、锁屏 30–60 分钟、实际 15 分钟淡出、耳机断开/来电/音频抢占、文件提供方导入、覆盖安装、飞行模式和 8 小时整晚播放。

具体阻塞和用户最小操作：在 Xcode 登录自己的 Apple ID，给 `MinimalSleep` target 选择真实 Personal Team；连接并解锁 iPhone，完成“信任此电脑”和 Developer Mode 后选择真机 Run。不要把 Team ID、证书或描述文件提交到 Git。

下次从哪个步骤继续：先完成 `docs/ios-validation.md` 的真机短测，再做锁屏 30–60 分钟和实际 15 分钟定时，最后安排不连接调试器的 8 小时整夜验证。录音和分类仍属于后续阶段。
