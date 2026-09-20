# 验证记录

日期：2026-09-20。所有结果均需注明命令、退出码和证据路径；未执行的项目不能记为通过。

## 环境初检

- 仓库：`main...origin/main`，`779d10c first commit`，工作区初始干净，只有 `README.md`。
- 当前目录及其上级未找到适用的 `AGENTS.md`。
- `java`、`gradle`、`adb`、`emulator`、`kotlinc` 不在 PATH；`ANDROID_HOME`/`ANDROID_SDK_ROOT` 未设置；常见 Android Studio/SDK/JDK 路径未找到。
- 普通沙箱命令无法访问 GitHub；已开始尝试从官方地址下载构建工具。构建、安装和音频实测尚未完成。
- Android 命令行工具 `commandlinetools-win-15859902_latest.zip`：SHA-256 `90AE805D20434428BFFCB699C290860F19BB5F66A67E6B330067E3DE801FB04A`，与 [Android 官网](https://developer.android.com/studio) 公布的值一致。
- Gradle `gradle-8.13-bin.zip`：SHA-256 `20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78`，与 [官方校验文件](https://services.gradle.org/distributions/gradle-8.13-bin.zip.sha256) 一致。
- Amazon Corretto 17.0.20.1：完整压缩包 188084668 字节，MD5 `cbad55c3317e5ec8f59493d6d33ca3cc`，与 [AWS 官方 MD5 链接](https://corretto.aws/downloads/latest_checksum/amazon-corretto-17-x64-windows-jdk.zip) 一致；`java -version` 退出码 0。原本误命名为 `.sha256` 的下载校验文件实际上包含 MD5，保留原文件未覆盖。自动审批拒绝覆盖该文件的请求。
- Android SDK API 36 归档 `platform-36_r02.zip` SHA-1 `2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576`；Build Tools 35 Windows 归档 `build-tools_r35_windows.zip` SHA-1 `af059bb67cf7786f45ee0db85e2d24985df1b4b6`；均与 Google [SDK 仓库元数据](https://dl.google.com/android/repository/repository2-1.xml) 一致。官方 `sdkmanager` 因 ZIP 读取失败退出码 1，改为校验后解压到 `.tools/android-sdk-ready`。`android.jar` 与 `aapt2.exe` 均已存在。
- `python -m unittest discover -s tools -p test_generate_noise.py`：退出码 0，2 个测试通过。白、粉红、棕噪声各 20 秒、48 kHz、单声道 PCM 16-bit，文件哈希在 `assets-manifest.csv`。
- `gradle help` 首次直接访问官方 Maven 失败，Java TLS 握手中断（退出码 1）。本机运行 `tools/dev_maven_proxy.py` 通过 Python 从官方仓库读取公开依赖；代理首次构建仍因大 JAR 本地读取超时退出码 1，正在增加读取超时并重试。

## M0 工程空壳

- 构建环境：Amazon Corretto JDK 17.0.20.1、Gradle 8.13、AGP 8.13.2、Kotlin 2.3.21、Compose BOM 2026.05.00、compileSdk 36、targetSdk 35、minSdk 26。机器缺少系统级 JDK/SDK，本次使用 `.tools/` 中的经校验便携工具链；Gradle 依赖通过 `tools/dev_maven_proxy.py` 从官方 Maven 地址下载并缓存在 `.tools/`。
- 首次 `gradle help` 失败是 `kotlinOptions.jvmTarget` 已在 Kotlin 2.3.21 中变为错误，改用 `compilerOptions` 后 `gradle help` 退出码 0。
- 首次 `assembleDebug` 因本地代理未映射 AndroidX Gradle Module Metadata 的 AAR 文件名和 URL 退出码 1；修复代理并验证 `savedstate-release.aar` 正确取回 141149 字节。
- Compose BOM 2026.09.00 的 Compose 1.12.1 要求 AGP 9.1/API 37，`checkDebugAarMetadata` 实际退出码 1。改为 BOM 2026.05.00，检查 `foundation-android:1.11.1` AAR 元数据要求最低 AGP 8.6/API 35。
- `gradle --no-daemon --console plain assembleDebug`：退出码 0；日志 `.tools/assemble-m0-compatible.log` 末尾 `BUILD SUCCESSFUL in 7m 47s`，37 个任务，36 个执行、1 个已是最新。
- 输出 `app/build/outputs/apk/debug/app-debug.apk`，17162995 字节，SHA-256 `619AD9B2EAF7976DDB21983E135CA4151A23D44DF493F57BCDA0C9199B5D69ED`。`apksigner verify --verbose` 退出码 0，v2 签名校验通过。`aapt2 dump badging` 显示包名 `io.github.resker666.minimalsleep`、minSdk 26、targetSdk 35、可启动 Activity。
- `adb devices -l`：退出码 0，设备列表为空。因此未安装或启动 APK；双页面实际显示与旋转待真机确认。此 APK 仍是空壳，不能视为完成白噪声或监测产品。

## M1 播放器与 M2 录音实现

- M1 定时器测试先以 `NotImplementedError` 预期失败：`.tools/m1-timer-red2.log`，4 个失败。实现后 `testDebugUnitTest assembleDebug` 退出码 0：`.tools/m1-build-first.log`，43 个任务，输出三种声音、Media3 后台会话与今晚页。M1 APK 留存于 `deliverables/minimal-sleep-m1-debug.apk`；它是在后续 lint 修正之前留存的中间版本，推荐安装最终 M2 APK。
- 首次 M1 lint 退出码 1，6 个错误、6 个警告；错误为 Media3 错误码常量与 `UnstableApi` 标注，完整报告见当次 `.tools/m1-lint.log`。已修正，未使用 lint baseline 或关闭错误检查。
- M2 片段器测试先以 `NotImplementedError` 预期失败：`.tools/m2-segment-red.log`，3 个失败；实现后 `.tools/m2-segment-green.log`，退出码 0。测试覆盖前后缓冲、相邻触发合并、上限分段与同组 ID。
- WAV 写入测试先以 `NotImplementedError` 预期失败：`.tools/m2-wav-red.log`，1 个失败；最终测试通过，验证 RIFF/WAVE 头、长度、PCM 小端样本及无残留 `.part` 文件。
- M2 初次 `testDebugUnitTest assembleDebug` 退出码 0：`.tools/m2-build-first.log`。Room 版本 1 schema 已生成在 `app/schemas/io.github.resker666.minimalsleep.data.SleepDatabase/1.json`。这是编译和单元测试证据，尚非录音实测。
- M2 lint 首次退出码 1（2 个错误），修正 Media3 标注和运行时录音权限检查后，最终 `lintDebug testDebugUnitTest assembleDebug` 退出码 0：`.tools/m2-final-check2.log`，`BUILD SUCCESSFUL in 59s`，58 个任务。测试报告 `app/build/reports/tests/testDebugUnitTest/index.html`，lint 报告 `app/build/reports/lint-results-debug.html`；lint 仍有 6 项非阻断警告（目标 API、旧 Compose BOM、导出 MediaSessionService、kapt 等），原因/限制见技术决策与源码。共 8 个 JVM 测试通过；Python 噪声生成测试另有 2 个通过。
- 首个 M2 调试 APK（后续已有 r2）：`deliverables/minimal-sleep-m2-debug.apk`，24585857 字节，SHA-256 `748F4BA0FBE704184274888B41CF2089333482102A6612EFDE89D35AB6DC6062`。`apksigner verify --verbose` 退出码 0，v2 签名通过；`aapt2 dump permissions` 只列出前台服务（播放/麦克风）、`RECORD_AUDIO`、Media3 的 `WAKE_LOCK` 及 AndroidX 内部动态接收器权限，无 `INTERNET` 或网络状态权限。`aapt2 dump badging` 显示 minSdk 26、targetSdk 35、MainActivity 可启动。

## 真机验证（进行中）

- 2026-09-20，ADB 识别手机 `23127PN0CC`，Android API 36，状态 `device`。手机连接属于本轮新增条件，替代 M0 先前的“无设备”结论。
- `adb install -r app/build/outputs/apk/debug/app-debug.apk` 初次及用户开启“通过 USB 安装”后的重试均退出码 1：`INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`。非流式安装也同样失败。未绕过手机安装限制。
- `adb push deliverables/minimal-sleep-m2-debug.apk /sdcard/Download/minimal-sleep-m2-debug.apk` 退出码 0，手机端文件大小 24585857 字节。等待用户在文件管理器手动安装；因此 `am start`、播放、麦克风、回听、锁屏、整夜等尚无实测结论。
- 修复 MediaSessionService 重建时进程内 UI 状态未复位的问题后，重新执行 `lintDebug testDebugUnitTest assembleDebug`：退出码 0，`.tools/m2-final-check3.log`，`BUILD SUCCESSFUL in 1m 1s`。最新版 `deliverables/minimal-sleep-m2-debug-r2.apk` 为 24585857 字节，SHA-256 `7E910745B1EBF043F8E00C9F15C7A07C9B478E185C9E64538B0BBCFA54B4DE02`。`apksigner verify --verbose` 再次确认 v2 签名，`aapt2 dump permissions` 再次确认无 `INTERNET`。`adb push` 将它复制到手机 `下载/minimal-sleep-m2-debug-r2.apk`，原副本未覆盖。请安装 `r2` 版本。
- 用户经手机文件管理器安装 `r2` 后，`adb shell pm path io.github.resker666.minimalsleep` 返回 `base.apk`；`adb shell sha256sum` 返回 `7e910745b1ebf043f8e00c9f15c7a07c9b478e185c9e64538b0bbcfa54b4de02`，与本机副本完全一致；`adb shell am start -n io.github.resker666.minimalsleep/.MainActivity` 退出码 0，实际启动成功。原先“尚未安装”只描述前一阶段，不再代表现状。
- 真机短测：用户确认白噪声可听；完成一次约 4 秒有效采集，应用私有目录有 157740 字节 WAV（44 字节头 + 78848 个 16-bit 样本，约 4.928 秒）；“记录”页显示 1 个普通声音片段、1 个事件组、0–4 秒 `WHITE` 播放区间与“播放声音期间，识别可能受影响”标记。用户确认点击回听后原音可听。仅查看文件名/大小与界面，没有复制或上传手机录音内容。
- 同进程 `logcat --pid` 可见 AudioRecord 正常 stop/release 与 MediaController 初始化；截取的最近日志没有本 App 的未捕获异常。设备系统音频组件仍打印 `AudioTrack` 低功耗 XML 缺失提示，尚未观察到功能失败。粉红/棕噪声、定时到期、锁屏长期运行及回声误报对照仍待测试；本次短录音不足以证明整夜可靠。
- 后续约 2 分钟 ADB UI 短测：粉红、棕噪声选择项均能切换；MediaSession `metadata` 显示“棕噪声”，`state=PLAYING`，用户确认两种声音均可听见。白、粉红、棕三种声音均已获得主观可听确认，尚未检验 20 秒 WAV 循环处是否有可感知停顿。
- 棕噪声播放时 `adb shell input keyevent 26` 让屏幕进入 `Dozing`，4 秒后 `dumpsys media_session` 仍显示 `PLAYING`；`dumpsys activity services` 显示 `SoundPlaybackService` 为 `isForeground=true`、媒体前台通知 ID 1001。屏幕关闭时 `keyevent 85`（媒体播放/暂停）后状态转为 `PAUSED`。这仅是短时锁屏验证，不代表整夜后台可靠。
- 真机点击 15 分钟后界面显示“剩余约 15 分钟”，点击整晚后显示“整晚播放”；单元测试另验证四个到期值。尚未实际等到 15 分钟结束，因此定时自动停止与 10 秒淡出未列为真机通过。测试结束已主动暂停播放。

## 大雨与海浪优先更新（2026-09-20）

- 用户要求今晚先提供大雨、海浪以便试用，并把约 30 分钟锁屏录音安排到稍后；本轮未启动长时录音。
- 新增 `tools/generate_nature.py`，固定种子合成 24 秒大雨和 40 秒海浪。来源、生成方法及 SHA-256 在 `docs/assets.md`、`assets-manifest.csv`；没有引入第三方录音。源 WAV 为 48 kHz、单声道、16-bit。分析文件显示大雨 1 秒窗口 RMS 0.1713–0.2525，海浪 0.0117–0.1888，峰值约 0.64，首末 PCM 样本相同；这些是文件检查，不代表真机听感。
- 新测试 `test_generate_nature.py` 在模块创建前先运行，因 `ModuleNotFoundError` 退出码 1；实现后 `python -m unittest discover -s tools -p 'test_*.py'` 退出码 0，4 个 Python 测试通过，验证可重建、幅度、首尾连续与海浪起伏。
- 更新 `SoundCatalog` 和今晚页，两种自然声置于首行，默认选中大雨；三种原噪声仍可选择。版本号升为 0.2.0-dev（versionCode 2），保持相同包名与本机调试签名以便覆盖安装。
- `lintDebug testDebugUnitTest assembleDebug` 退出码 0，`.tools/nature-build.log` 末尾 `BUILD SUCCESSFUL in 1m 21s`，58 个任务；8 个 JVM 单元测试通过。APK `deliverables/minimal-sleep-nature-debug.apk` 为 27145533 字节，SHA-256 `4CA6B8E041BA79210A56C0AE3AEC7116A164B10AE019D254781C3B5F71E73171`。`apksigner verify --verbose` 显示 v2 签名有效；`aapt2 dump badging` 显示 versionCode 2、minSdk 26、targetSdk 35；`aapt2 dump permissions` 未列出 `INTERNET`。APK ZIP 内有 `res/raw/heavy_rain.wav`（2304044 字节）及 `res/raw/ocean_waves.wav`（3840044 字节）。
- `adb push` 将 APK 写入手机 `/sdcard/Download/minimal-sleep-nature-debug.apk`，手机文件大小 27145533 字节。由于 ADB 安装此前被手机拒绝，正在等待用户从文件管理器手动更新；安装和两种自然声听感尚未验证，不能列为通过。

### 安装后短测顺序

1. 打开 App；只播放白、粉红、棕三种声音各 1 分钟，检查循环点、音量、通知暂停、锁屏继续、耳机拔出暂停与其他应用抢占焦点。记录设备音量、路由与异常。
2. 设置 15 分钟计时，再做 30/60/90 分钟和整晚的短时钟模拟或实际等待；检查旋转、离开页面与手动暂停不会意外重置定时。单元测试只验证计算，不能替代真实服务时序。
3. 拒绝麦克风权限：确认仅播放仍可用。授权后做 2–5 分钟仅录音，制造几次可识别的普通声音，结束后在“记录”页回听原音、删除单条与整夜记录。请勿使用私人录音作为提交样本。
4. 同时播放白噪声和录音，检查时间轴有播放区间、重叠片段有干扰标记；记录白噪声音量与摆位。回听时先停止录音。
5. 短测通过后做至少 30 分钟锁屏试录；记录实际有效样本时长、缺口、音频占用、起止电量和系统后台限制。随后安排 8 小时整夜测试；未完成之前状态保持“待验证”。
