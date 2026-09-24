# iOS validation

## 2026-09-24 本地生成与模拟器复验

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
| 新版 GitHub Actions | 等待本分支推送后的实际运行 | 未测 |
| iPhone 基础播放与锁屏控制 | 用户暂时不能配合真机 | 未测 |
| 两次循环边界与真实 15 分钟淡出 | 需要人耳与真机观察 | 未测 |
| 路由、中断、导入、覆盖安装、飞行模式 | 需要真机操作 | 未测 |
| 8 小时整夜播放 | 需要真机长时测试 | 未测 |

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
