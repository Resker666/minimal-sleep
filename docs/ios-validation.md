# iOS validation

## 2026-09-24 夜间声音片段录音本地验证

分支：`codex/ios-night-recording`。环境：Xcode 27.0、iPhone 18 Pro / iOS 27.0 模拟器。以下结果来自本机命令；云端 CI 与真机录音另行记录。

| 检查 | 命令或证据 | 实际结果 |
|---|---|---|
| 音频准备工具 | `/opt/homebrew/bin/python3.12 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v` | 退出码 0；6/6 通过 |
| 完整 iOS XCTest | `xcodebuild test -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -parallel-testing-enabled NO -derivedDataPath /private/tmp/minimal-sleep-recording-final-tests-serial CODE_SIGNING_ALLOWED=NO` | 日志显示 91/91 用例通过、0 失败；`xcodebuild` 两次在用例结束后超过两分钟仍未退出，均发送 TERM 后退出码 143，因此本机没有完整命令退出码 0 |
| Release 模拟器构建 | `xcodebuild build -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/minimal-sleep-recording-final-release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` | 退出码 0；`BUILD SUCCEEDED` |
| 通用 iPhone 构建 | `xcodebuild build -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/minimal-sleep-recording-final-device CODE_SIGNING_ALLOWED=NO` | 退出码 0；`BUILD SUCCEEDED`。无签名，不可安装 |
| App 包 | 检查 Release `MinimalSleep.app/Info.plist` 与资源文件 | `0.5.0 (2)`；麦克风用途说明和后台 `audio` 存在；两段雨声 M4A 与三段小 WAV 存在；旧的两个大 WAV 不存在 |
| 隐私与源码 | `git ls-files`、项目签名设置 diff、忽略文件检查 | 没有跟踪夜间录音、`.wav.part` 或 Personal Team 字段；两段生成 M4A 被忽略 |
| Android 版本 | `app/build.gradle.kts` | 仍为 `versionCode 5`、`versionName "0.4.0-dev"` |
| 真机可用性 | `xcrun devicectl list devices` | 首次 CoreDeviceService 初始化超时；再次查询退出码 0，`朱颜辞镜花辞树` 为 `unavailable`。未安装、未录音 |
| iOS GitHub Actions | [iOS Simulator App #11](https://github.com/Resker666/minimal-sleep/actions/runs/36015988792)，提交 `ac34f0d6f9d4` | 工作流与 build job 均成功；iOS tests、Release build、包资源检查、Artifact 上传步骤成功。公开运行中日志不可读，云端测试数量未单独确认 |
| iOS 云端 Artifact | `minimal-sleep-ios-simulator-11` | GitHub API 大小 17,838,226 字节；摘要 `sha256:4e1d066e845f15b99d5fdb0637867cc39b6091e8aab51ef0fb816a69081363f7`；到期 2026-10-08 14:59:14 UTC；仅供模拟器使用 |
| Android GitHub Actions | [Android APK #29](https://github.com/Resker666/minimal-sleep/actions/runs/36015988618)，提交 `ac34f0d6f9d4` | 工作流成功；Artifact `minimal-sleep-debug-29`，55,822,073 字节；本轮未下载 APK 或安装 Android 真机 |

新增自动测试覆盖能量触发、前后缓冲、60 秒分片、WAV 格式、存储故障回滚与恢复、播放区间定期保存、音频会话切换、中断停止、录音权限、记录列表、回听切换与删除。存储故障、播放区间和回听切换检查先出现预期失败，修复后定向测试均以退出码 0 通过。本机日志保存在 `/private/tmp/minimal-sleep-recording-final-python.log`、`/private/tmp/minimal-sleep-recording-final-tests-serial.log` 和 `/private/tmp/minimal-sleep-recording-final-release.log`，均不进入 Git。提交前一次完整 90 项 XCTest 曾以退出码 0 完成；增加回听切换测试后的两次 91 项运行只有用例结论，等待 CI 独立验证整个命令。

**未测：** 真机麦克风授权允许/拒绝、实际采样与听感、助眠声干扰、锁屏 30 分钟、耳机断开/来电、回听/删除、覆盖安装保留私有数据、8 小时整夜可靠性。模拟器自动化不证明这些项目。录音文件未从手机读取或上传。

## 2026-09-24 AAC/M4A 压缩复验

验证分支为 `codex/ios-reliability`。环境为 macOS 27.0、Xcode 27.0、Homebrew Python 3.12.14、FFmpeg/FFprobe 9.0.2，以及 iPhone 18 Pro / iOS 27.0 模拟器 `75FA9690-7229-4F85-96C1-284AD9262383`。

| 检查 | 实际结果 | 状态 |
|---|---|---|
| `test_prepare_ios_audio.py` | 6 个测试通过，0 失败 | 通过 |
| M4A 确定性生成 | 在全新临时目录重新生成，两个文件及两份清单逐字节一致 | 通过 |
| `rain-01.m4a` | 298 秒、AAC、44.1 kHz、双声道、4,834,016 字节；SHA-256 `ea9a392d6e262d19db2c9ef8c1bb31ce81db2ecc420d11fd474217e7d15594fc` | 通过 |
| `rain-04.m4a` | 298 秒、AAC、44.1 kHz、双声道、4,859,928 字节；SHA-256 `b779392b3ff4c7a24d2459477c4d8e28969cb123e1989c507942266e385ca85b` | 通过 |
| iOS XCTest | 33 个测试通过，0 失败；包含两个 M4A 的 Bundle 查找和 `AVAudioPlayer` 加载/时长检查 | 通过 |
| Release 模拟器构建 | `** BUILD SUCCEEDED **` | 通过 |
| App 包资源 | 两段 M4A 和三段 WAV 均存在且非空；旧 `rain-01.wav`、`rain-04.wav` 不存在 | 通过 |
| App/ZIP 大小 | App 目录约 18 MB；本机 `ditto` ZIP 约 17 MB | 通过 |
| 签名的通用 iPhone 构建 | 使用本机 Personal Team 构建 Debug iPhone App；`codesign --verify --deep --strict` 通过，尚未安装到手机 | 通过 |
| M4A GitHub Actions | [运行 #9](https://github.com/Resker666/minimal-sleep/actions/runs/35965815562)，提交 `ebdc0da253b3`，生成、清单、33 个 XCTest、Release 构建、资源检查和上传全部成功；总耗时 7 分 39 秒 | 通过 |
| 云端 Artifact | `minimal-sleep-ios-simulator-9`，17,463,485 字节，摘要 `sha256:307068595dbe1ba0d0ac5d3dcf382482bf9369f13b026a33844029727312d9cf`，到期时间 2026-10-08 06:50:11 UTC | 通过 |
| M4A 真机播放与两次循环 | 需要用户听感确认 | 未测 |

AAC 是有损压缩。自动验证能够确认格式、时长、大小、哈希、Bundle 包含关系和 AVAudioPlayer 能加载，但不能证明真实扬声器上的循环接缝听不出。运行 #9 的 Artifact 比运行 #8 的 PCM Artifact 减少约 82.3%；云端产物仍是未签名模拟器 App，不能安装到 iPhone。

## 2026-09-24 PCM WAV 基线复验

验证分支为 `codex/ios-reliability`，验证时提交为 `3e2e902ba59e`。环境为 macOS 27.0 (`26A428`)、Xcode 27.0 (`27A266a`)、Apple Python 3.9.6、Homebrew FFmpeg 9.0.2，以及已启动的 iPhone 18 Pro / iOS 27.0 模拟器 `75FA9690-7229-4F85-96C1-284AD9262383`。

| 检查 | 实际结果 | 状态 |
|---|---|---|
| `test_prepare_ios_audio.py` | 4 个测试通过，0 失败 | 通过 |
| 由 Ogg 生成两个 PCM WAV | `rain-01.wav` 与 `rain-04.wav` 生成成功，均为 52,567,278 字节 | 通过 |
| `rain-01.wav` SHA-256 | `bdfda7d0dec01eaf65eb006bc2f09d1276ec11ac601120d28e7797c35e958269` | 通过 |
| `rain-04.wav` SHA-256 | `3f66e5b609802376af96221911f50d474ef42239b449c80c22c911c742a5b8dc` | 通过 |
| 派生清单 | `assets-manifest.csv` 与 `audio-derivations.json` 生成前后无 diff | 通过 |
| Git 状态 | 两个生成 WAV 被忽略且未跟踪 | 通过 |
| iOS XCTest | 31 个测试通过，0 失败；`** TEST SUCCEEDED **` | 通过 |
| Release 模拟器构建 | 禁用签名构建成功；`** BUILD SUCCEEDED **` | 通过 |
| App 包资源 | 主可执行文件及 `rain-01.wav`、`rain-04.wav`、`heavy_rain.wav`、`ocean_waves.wav`、`white_noise.wav` 均存在且非空 | 通过 |
| 新版 GitHub Actions | [运行 #8](https://github.com/Resker666/minimal-sleep/actions/runs/35960026403)，提交 `9f9e9a17bac4`，全部关键步骤成功，6 分 58 秒 | 通过 |
| iPhone 基础播放与锁屏控制 | 用户暂时不能配合真机 | 未测 |
| 两次循环边界与真实 15 分钟淡出 | 需要人耳与真机观察 | 未测 |
| 路由、中断、导入、覆盖安装、飞行模式 | 需要真机操作 | 未测 |
| 8 小时整夜播放 | 需要真机长时测试 | 未测 |

### GitHub Actions 运行 #6 至 #8

- [运行 #6](https://github.com/Resker666/minimal-sleep/actions/runs/35958149518) 在提交 `4f1587ca3991` 上失败，总耗时 33 秒。Set up Python、Install FFmpeg 与环境检查成功；Prepare generated iOS audio 的 4 个测试和转码成功，但 runner 从旧 Homebrew 元数据安装了 FFmpeg 9.0.1_1，生成哈希为 `cccd0b628f56c9b28745b9bf4ef0483602c73c04c665f847aa381cbf8707e6db` 与 `28ad36aa5439f31a2ffd963a5af23f634706374e0a5a0094ee527b5c0b45b4db`，与 9.0.2 派生清单不一致，清单 diff 使步骤退出 1；后续测试、构建与上传均跳过。
- 修复提交 `a9d4c7e5089c` 在安装前运行 `brew update`，并要求实际 FFmpeg 版本等于 9.0.2。没有删除清单一致性检查。
- [运行 #7](https://github.com/Resker666/minimal-sleep/actions/runs/35958729555) 状态 Success，总耗时 5 分 44 秒。Set up Python 3.12、Install FFmpeg、Prepare generated iOS audio、Run iOS tests、Build unsigned simulator app、Verify and package simulator app、Upload simulator app 与下载链接步骤均为 success。
- 产物 `minimal-sleep-ios-simulator-7` 的 GitHub API 大小为 98,676,086 字节，页面显示 94.1 MB，外层摘要为 `sha256:90281f002c7e4f4bedef08fb837d2f369ded5f2bd358259114acfb9be0ce302d`，到期时间为 2026-10-08 05:15:25 UTC。
- 已在登录状态下载运行 #7 Artifact。Safari 自动解开外层 ZIP 后，目录中有 `MinimalSleep-iOS-Simulator.zip`（98,675,644 字节）和 `MinimalSleep-iOS-Simulator.zip.sha256`；内部 ZIP 实算 SHA-256 为 `6ffcce703d221ed8d17d87ca8eacae8391fbea8edc01f412d09317106aa33fb1`，与随包文件一致。随包文件当时记录了 CI 工作目录前缀 `dist/`，因此在自动解开的目录中按实际文件名比较哈希。
- 最终复查提交 `9f9e9a17bac4` 让 `.gitignore` 变更触发工作流，以 `assert_ignored` 拒绝反向取消忽略的规则，并让校验文件只记录包文件名。修复后的 [运行 #8](https://github.com/Resker666/minimal-sleep/actions/runs/35960026403) 状态 Success，总耗时 6 分 58 秒；所有构建步骤及收尾步骤均为 success。
- 运行 #8 产物 `minimal-sleep-ios-simulator-8` 的 GitHub API 大小为 98,676,081 字节，外层摘要为 `sha256:54a1ddf2c83a6a9cd92b026e72a9a2e8ccc4e9b09c847f593139e562b3fd4271`，到期时间为 2026-10-08 05:34:21 UTC。打包步骤已在 `dist` 目录中直接执行 `shasum -a 256 -c MinimalSleep-iOS-Simulator.zip.sha256` 并成功；本机尚未独立下载运行 #8 产物。

本次运行命令使用仓库文档中的生成命令，以及 `CODE_SIGNING_ALLOWED=NO` 的 Debug XCTest 和 Release 模拟器构建。结果包保存于 `/tmp/minimal-sleep-ios-reliability-tests.xcresult`，构建输出位于 `/tmp/minimal-sleep-ios-reliability-release`；二者均为本机临时证据，不进入 Git。模拟器和无签名构建不能证明真实扬声器听感、锁屏连续性、路由安全、耗电或整夜可靠性。

## 2026-09-23 历史证据

Updated: 2026-09-23. Automated evidence was collected on macOS 27.0 (`26A428`) with Xcode 27.0 (`27A266a`). The build commit field remains `未提交` because the Mac implementation is currently a reviewable working-tree change on `codex/ios-mvp` after merge commit `b37aba5`.

| Test | Device / OS / Xcode | Build commit | Conditions | Actual result / evidence | Status |
|---|---|---|---|---|---|
| Swift source compile | Apple silicon Mac / Xcode 27.0 | 未提交 | App and test targets | XCTest build completed | 通过 |
| XCTest: timer, coordinator, imports, decode, catalog, preferences | iPhone 18 Pro simulator / iOS 27.0 | 未提交 | Injected monotonic clock, fake storage/capacity, real bundled WAV decode | 31 passed, 0 failed, 0 skipped | 通过 |
| Simulator generic build | iOS Simulator SDK 27.0 | 未提交 | Debug, `CODE_SIGNING_ALLOWED=NO` | `xcodebuild` exit 0 | 通过 |
| Simulator install and launch | iPhone 18 Pro simulator / iOS 27.0 | 未提交 | Five bundled WAV files | `simctl install` and `launch` exit 0; first screen rendered | 通过 |
| Generic iOS device build | iOS SDK 27.0 / arm64 | 未提交 | Debug, unsigned | `xcodebuild` exit 0; this does not install to a phone | 通过 |
| Bundle resources and privacy keys | Simulator and device app bundles | 未提交 | Inspect built bundles and Info.plist | Both contain 5 WAV files; background `audio` present; microphone key absent | 通过 |
| Launch, switch, pause, volume | Physical iPhone | 未提交 | Short listening test | Device listed as unavailable; not run | 未测 |
| Each rain track crosses two loop boundaries | Physical iPhone | 未提交 | User listening; each track is 298 seconds | PCM format/hash verified; audible seam, pop, and silence not tested | 未测 |
| Locked playback for 30–60 minutes | Physical iPhone | 未提交 | Screen locked, no debugger keepalive | Not run | 未测 |
| Actual 15-minute deadline and final 10-second fade | Physical iPhone | 未提交 | Screen locked | Policy/scheduler tests pass; real-time phone test not run | 未测 |
| Headphone removal, call, and audio interruption | Physical iPhone | 未提交 | Manual route/interruption tests | Notification handling compiled and coordinator test passes; physical behavior not run | 未测 |
| Local/provider MP3, M4A, WAV import and cancel | Physical iPhone | 未提交 | Legal user-selected fixtures | Store limits/transactions and bundled WAV decode tests pass; provider flow not run | 未测 |
| Delete current item and rapid switching | Physical iPhone | 未提交 | Device stress sequence | Delete-before-remove and stale-timer tests pass; physical stress test not run | 未测 |
| Force quit, relaunch, and overwrite install | Physical iPhone | 未提交 | Preserve private imports; do not uninstall | JSON reopen and preference tests pass; installation update not run | 未测 |
| Airplane mode | Physical iPhone | 未提交 | Built-in and imported playback | No runtime networking dependency; not run | 未测 |
| Eight-hour overnight playback | Physical iPhone | 未提交 | Record battery, charging, low-power mode, screen, route, duration, temperature | Not run | 未测 |

## Commands and results

### XCTest

```bash
xcodebuild -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=75FA9690-7229-4F85-96C1-284AD9262383' \
  -derivedDataPath /tmp/minimal-sleep-final-tests-derived \
  -resultBundlePath /tmp/minimal-sleep-final-tests.xcresult \
  test -quiet
```

Exit code 0. The final result reported 31 total tests, all passed. Tests cover timer deadlines and fade ratios, long UI gaps, pause/stop rules, background scheduler expiry, paused sound switching, stale callbacks, unsafe audio events, runtime decode failure, stopped/expired remote commands, imported playback URLs, preference restoration without autoplay, import limits/transactions, staging byte accounting, corrupt-index recovery, restart index reads, delete-before-file-removal, catalog metadata, and complete AVAudioFile reading of a bundled WAV plus rejection of invalid bytes.

### Builds

```bash
xcodebuild -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/minimal-sleep-final-sim-build \
  build CODE_SIGNING_ALLOWED=NO -quiet

xcodebuild -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/minimal-sleep-final-device-build \
  build CODE_SIGNING_ALLOWED=NO -quiet
```

Both commands exited 0. Unsigned device compilation only verifies the device architecture and SDK build; it is not installable.

### Audio preparation

```bash
/opt/homebrew/bin/python3.12 -m unittest discover \
  -s tools -p 'test_prepare_ios_audio.py' -v

/opt/homebrew/bin/python3.12 tools/prepare_ios_audio.py \
  --ffmpeg /opt/homebrew/bin/ffmpeg
```

Both commands exited 0. The two outputs are 298-second, 44.1 kHz, stereo, 16-bit PCM WAV files. SHA-256 values:

- `rain-01.wav`: `bdfda7d0dec01eaf65eb006bc2f09d1276ec11ac601120d28e7797c35e958269`
- `rain-04.wav`: `3f66e5b609802376af96221911f50d474ef42239b449c80c22c911c742a5b8dc`

Running every Python tool test produced 10 passes and 4 failures. All four failures are existing Ogg-output tests in `test_prepare_loop.py`; Homebrew's regular FFmpeg 9.0.2 exposes the native Vorbis encoder but not the script's required `libvorbis` encoder. The failure is retained as environment evidence and was not reported as a pass.

## Physical-device handoff

`xcrun devicectl list devices` sees `朱颜辞镜花辞树` (iPhone18,1) but reports it as `unavailable`. After the phone is connected, unlocked, trusted, Developer Mode is enabled, and a real Personal Team is selected in Xcode, execute the rows above in order. Record the output route and exact device/iOS/Xcode versions. A simulator launch does not establish actual speaker output, lock-screen continuity, audible loop quality, route safety, or overnight reliability.
