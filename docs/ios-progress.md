# iOS progress

当前任务：无 Mac 首轮准备；只交付源码树、纯逻辑 XCTest、资源转码脚本/可直接复用的 PCM WAV、忽略规则和交接文档。

起始提交 / 当前分支：`2e22a7405551ec5f9540657d06388a44f098aba4` / `codex/ios-mvp`。

本轮已完成：建立计划第 4 节的 Swift 源码与测试目录；按 Android 实际代码固化 15/30/60/90/整晚、单调截止、最后 10 秒线性淡出、暂停不延长、停止清除、改时长重计和过期远程命令不恢复；导入上限统一为 10 个、100 MiB/文件、300 MiB 总量、复制后至少 200 MiB，并以 actor 串行提交、UUID 内部名和失败清理保护索引；声音目录含两段 Resker666 / CC BY 4.0 雨声、白噪声、程序近似的合成大雨/海浪。三段仓库 PCM WAV 复制到 iOS 资源目录后按哈希核对。AVFoundation/MediaPlayer 仅有协议、状态机调用点和 `TODO（需 Mac 编译）`，没有伪造播放器。

构建与测试（实际命令、退出码）：使用 Codex bundled Python 执行 `python.exe -m py_compile tools/prepare_ios_audio.py tools/test_prepare_ios_audio.py`，退出码 0；`python.exe tools/prepare_ios_audio.py --help`，退出码 0；实际执行 `python.exe tools/prepare_ios_audio.py`，因未找到 FFmpeg 按预期退出码 1，并明确输出“没有音频文件被修改”；`python.exe -m unittest discover -s tools -p 'test_*.py' -v`，退出码 0，共 14 个测试完成，其中 6 个依赖 FFmpeg 的既有循环剪辑测试跳过，新增的 4 个 iOS 转码脚本测试全部通过；`python.exe -m compileall -q tools`，退出码 0；`git diff --check`，退出码 0。`assets-manifest.csv` 中 8 个实际资源全部存在且哈希一致，退出码 0；三份 iOS PCM WAV 以 Python `wave` 读取均为 48 kHz、单声道、16-bit、未压缩 PCM，退出码 0。本机没有 Swift/Xcode，XCTest、iOS build、simulator build 均未运行，不得记为通过。未运行 Android Gradle 构建，因为本轮未修改 Android 源码或 Android 原资源，且 AGENTS.md 指定的四个本地工具缓存目录当前均不存在。

真机已验证：无。本轮没有 Mac、iPhone 真机或模拟器，不复用 Android 结果冒充 iOS 证据。

真机未验证：启动/播放/切换/音量、两段雨声各跨至少两次完整循环的听感、锁屏 30-60 分钟、实际 15 分钟到期和 10 秒淡出、耳机/来电/焦点、MP3/M4A/WAV 导入、删除当前曲目、快速操作、覆盖安装、飞行模式与 8 小时整晚播放全部未测。

具体阻塞和用户最小操作：当前 Windows 环境无 `ffmpeg`/解码器，`rain-01.wav`、`rain-04.wav` 和派生清单尚未生成；无 Swift/Xcode，源码和测试无法编译。今晚在 M4 从任务 0 环境核验开始，运行 `python3 tools/prepare_ios_audio.py`，再按 `ios/README.md` 建真实 Xcode 工程并完成所有 `TODO（需 Mac 编译）`。Personal Team 登录、真机信任与 Developer Mode 只能由用户操作。

下次从哪个文件/步骤继续：先从 `docs/minimal-sleep-ios-codex-plan.md` 任务 0 开始；随后按 `ios/README.md` 创建工程、加入本轮已有源码/测试/资源，不重写这些纯逻辑文件；从 `AudioCoordinator.swift` 的 AVFoundation engine、`NowPlayingController.swift` 的 MediaPlayer 注册、`ImportedSoundStore.swift` 的音频校验和 App 依赖装配继续。
