# 验证记录

初建：2026-09-20；更新：2026-09-24。所有结果均需注明命令、退出码和证据路径；未执行的项目不能记为通过。

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

## 构建环境交接验证（2026-09-20）

- 仓库已推送到公开的 `Resker666/minimal-sleep`，`main` 与本地 `c491883c336ff2c8e34755b0c4bf206b3aa88859` 一致；GitHub `v0.2.0-preview.1` 为预发布版，公开 API 返回 1 个 `uploaded` APK 附件、27145533 字节及与本地一致的 SHA-256。录音及 `.tools/` 未进入 Git。
- 在现有 Windows 工作区复用 `.tools`，不设置 `MINIMAL_SLEEP_MAVEN_PROXY` 而运行 `--offline` 时退出码 1：无法从不同仓库 URL 的缓存解析 Kotlin kapt 插件，日志 `.tools/offline-build-check.log`。
- 保留 `MINIMAL_SLEEP_MAVEN_PROXY=http://127.0.0.1:8765/m2` 并运行同一 `--offline` 构建，退出码 0：`.tools/offline-build-proxy-cache-check.log`，`BUILD SUCCESSFUL in 41s`，58 个任务、47 个已是最新。`--offline` 运行未访问代理网络。复用命令与新电脑要求见 `docs/development-setup.md`。

### 安装后短测顺序

1. 打开当前 App；分别播放两段雨声剪辑、白噪声及合成声音，检查循环点、音量、通知暂停、锁屏继续、耳机拔出暂停与其他应用抢占焦点。记录设备音量、路由与异常。旧版粉红、棕噪声现已移除。
2. 设置 15 分钟计时，再做 30/60/90 分钟和整晚的短时钟模拟或实际等待；检查旋转、离开页面与手动暂停不会意外重置定时。单元测试只验证计算，不能替代真实服务时序。
3. 拒绝麦克风权限：确认仅播放仍可用。授权后做 2–5 分钟仅录音，制造几次可识别的普通声音，结束后在“记录”页回听原音、删除单条与整夜记录。请勿使用私人录音作为提交样本。
4. 同时播放白噪声和录音，检查时间轴有播放区间、重叠片段有干扰标记；记录白噪声音量与摆位。回听时先停止录音。
5. 短测通过后做至少 30 分钟锁屏试录；记录实际有效样本时长、缺口、音频占用、起止电量和系统后台限制。随后安排 8 小时整夜测试；未完成之前状态保持“待验证”。

## 2026-09-21 续测：锁屏采集、本地模型与文件导入

- 从当前 `main` 干净状态 `729cdca` 建立 `codex/continue-m3-m5` 分支开发；原已公开预发布 `v0.2.0-preview.1` 未改动。手机 `23127PN0CC`，Android API 36，原安装 versionCode 2。`.tools/jdk/jdk17.0.20_10`、`.tools/android-sdk-ready`、`.tools/gradle/gradle-8.13`、`.tools/gradle-home` 均存在，沿用 `docs/development-setup.md` 的离线构建环境。未把手机录音复制到电脑或上传。
- 经用户允许，2026-09-21 07:52:19（UTC+8）启动“仅记录”，07:52:36 锁屏，`dumpsys power` 为 `Dozing`；录音服务持续显示 `isForeground=true foregroundId=1201`。超过 08:22:19 后经 App “结束记录”确认。记录页显示该会话 `COMPLETED`、有效采集 **1,918 秒**、18 个片段/18 个事件组、0 秒助眠声播放、未显示中断缺口；停止后前台录音服务不再存在。录音目录总占用 `adb shell run-as io.github.resker666.minimalsleep du -sk files/recordings` 为 10,976 KiB，但包含先前会话，不能归作本次用量。开始电量 19%、结束 25%，全程 USB 充电，不能据此估算不充电耗电。手机另有一条先前 28,006 秒 `COMPLETED` 记录，测试条件未知，不算本轮受控整夜测试。
- 模型来源、Apache-2.0 标注、归档/权重/标签 SHA-256 与 521 标签索引记录在 `docs/model-assets.md`。Python 版官方 LiteRT 对同一权重做了输入输出冒烟测试：16 kHz 单声道浮点 15,600 样本输入，`[1,521]` 输出；静音、仓库合成噪声/大雨/海浪均非鼾声准确率验收样本。`com.google.ai.edge.litert:litert:1.4.2` 及 API AAR/POM 从 Google Maven 获取到忽略的本地缓存。首次构建因本地代理网络 502 失败（`.tools/m3-build-first.log`）；手动从官方 Maven 缓存四个公开文件后 `.tools/m3-build-second.log` 成功。构建只下载公开依赖，App 无网络权限。
- Room schema v2 由构建生成在 `app/schemas/io.github.resker666.minimalsleep.data.SleepDatabase/2.json`；真机从 versionCode 2 升级到 3 再升级到 4，旧的 1,918 秒、28,006 秒与约 4 秒会话仍在记录页显示，旧片段标记“旧版录音，无自动分类”，因此至少在此设备上迁移保留成功。
- 本轮最终 `--offline --no-daemon --console plain lintDebug testDebugUnitTest assembleDebug` 退出码 0，日志 `.tools/m3-import-final-build6.log`：`BUILD SUCCESSFUL in 1m 31s`，58 个任务。15 个 JVM 测试、0 失败；新增分类规则测试 4 个、区间/分组统计测试 3 个。此前一轮 Lint 因 `MediaMetadataRetriever.use` 需要 API 29 而失败，见 `.tools/m3-import-final-build.log`；改为 `release()` 后通过，没有压制错误。代码审查发现的分类队列遗留状态、快速切声、导入/删除并发及切换期误删风险，已在最终构建前修正。
- 最终 APK `deliverables/minimal-sleep-v0.3.1-dev-debug-r4.apk`，51,446,126 字节，SHA-256 `684F16EA29479BE4BAE7BE6350A7C6F7CABA7254C0E05F3D1A8CB29B23A71FC1`。`apksigner verify --verbose` 显示 v2 签名有效；`aapt2 dump badging` 为 versionCode 4、versionName `0.3.1-dev`、minSdk 26、targetSdk 35；`aapt2 dump permissions` 仅列前台服务、麦克风、WAKE_LOCK 与应用内部动态接收器权限，`HasInternet=False`。`adb install -r` 返回 `Success`，`dumpsys package` 确认手机上 versionCode 4。此 APK 是本机调试签名，不是正式发布版。
- 从系统文件选择器选取**本仓库原创** `ocean_waves.wav` 测试（3,840,044 字节），导入后 `run-as` 可见 App 私有目录同大小 WAV；`dumpsys media_session` 显示 `PLAYING`、元数据为该导入文件，播放位置从 0 推进至 11,643 ms，随后可暂停。再次升级 App 后导入文件仍在；修正长文件名挤出按钮问题后，真机可见并点击“删除”，私有导入目录变为 `total 0`。推送到手机 `Download` 的原创测试源 WAV 经设备和本机 SHA-256 一致后已删除。未导入或查看用户自己的音频。
- 同时播放这段合成海浪并采集约 38 秒，记录页有 1 个 20.416 秒片段、1 个事件组、38 秒播放区间和播放干扰标记；本地模型实际加载，生成 `Speech` 未校准分数 0.59，初次显示“人声/疑似梦话”。这在已知只有合成海浪播放的测试中是明确误报。最终 0.3.1-dev 按播放干扰将该片段显示和计数为“未确定（播放干扰）”，仍显示原模型候选、分数与版本；真机升级后 UI 已核对为 `未确定（播放干扰）：0 / 1`。这只证明干扰标记与降级显示，不证明回声消除或分类准确率。App 测试结束已暂停播放。
- 最终 r4 安装后，ADB 快速点击“大雨→海浪→大雨”，`dumpsys media_session` 为大雨 `PLAYING`；再次选海浪并紧接媒体暂停按键，返回海浪 `PAUSED`。这是快速操作回归，不能保证覆盖所有 150 ms 时序排列。随后确认无录音前台服务且播放器为 `PAUSED`。
- `adb shell pm path io.github.resker666.minimalsleep` 找到已安装 `base.apk`；`adb shell sha256sum` 得到 `684F16EA29479BE4BAE7BE6350A7C6F7CABA7254C0E05F3D1A8CB29B23A71FC1`，与 r4 本地 APK SHA-256 完全一致，确认手机装的是最终修订包。
- 未完成验证：真实鼾声/人声/咳嗽分开的合法样本、误报/漏报、导入 MP3/M4A 等其他格式、定时实际到期/10 秒淡出、循环接缝、耳机拔出和焦点、权限拒绝、空间不足、来电/蓝牙、受控 8 小时整夜及不充电耗电。请勿从本节推断睡眠质量或呼吸暂停。

## 2026-09-21 用户素材本地循环试听准备

- 开始前 `git status --short --branch` 为干净的 `codex/continue-m3-m5`；本轮建立 `codex/loop-audio-previews`。`source/` 有 7 段 MP3，合计 301,860,865 字节（287.9 MiB）：两段 230.95 秒/508.82 秒，五段约 3,601–3,676 秒。`git ls-files --stage source` 为空，`.gitignore` 的 `*.mp3` 排除原件。没有发现这 7 段的许可文件或文件内版权标签；用户表示稍后提供授权信息，故没有加入源码、公开 APK 或 Release。目录中没有海浪素材。
- 新增 `tools/prepare_loop.py`：在原件不变、目标不存在的前提下，选取时段、尾首交叉淡化、限制 PCM 峰值并输出 Ogg Vorbis。先写 3 个测试，首次 `python -m unittest tools.test_prepare_loop -v` 退出码 1，因脚本尚不存在而有 2 个预期失败；实现后通过。增加响亮交叉区测试时先实际看到解码峰值 `1.4183` 导致失败；修复滤镜内部采样格式与限幅后通过。增加可选降低增益测试时先因未知 `--gain` 参数失败，实现后通过。增加目标文件竞态测试时先因缺少排他发布函数而失败，实现后通过，避免其他进程新建的文件被误删。最终 `python -m unittest discover -s tools -p 'test_*.py' -v` 退出码 0：10 个测试、0 失败，其中 6 个为新增剪辑测试。测试覆盖输出时长/接缝、拒绝覆盖、越界拒绝、交叉区削波、降低增益与发布竞态。
- 五段长雨声均从第 600 秒选取 300 秒、尾首交叉淡化 2 秒。最终仅以 `deliverables/audio-previews-v4/` 为候选；`manifest.json` 记录每段输入/输出 SHA-256、处理参数和 `permissionToRedistribute=UNVERIFIED`。五个 v4 Ogg 经 `ffprobe` 均为 298.000 秒、44.1 kHz 双声道 Vorbis，大小分别为 4,097,198、4,367,408、4,417,870、4,198,196、4,326,801 字节。全部经 FFmpeg `-xerror` 完整解码；各声道峰值最大 0.843，假定以 0.707/声道混合为单声道的峰值最大 0.930，首末单采样差各声道最大 0.0188。数值不能证明循环接缝听不出。早期 v1–v3 预览留在忽略目录中，仅 v4 为候选。
- 两段短 MP3 只复制为 `cicada-original.mp3` 与 `storm-original.mp3` 供试听，原文件未裁剪。蝉鸣音频以 0.1 秒窗、RMS 0.001 阈值检测，开头约 0.4 秒与结尾约 0.3 秒较安静，直接循环可能有音量低谷；雷雨声未显示同样的阈值下静音窗。仍需耳听验收。
- 用户允许短暂使用手机后，ADB 设备为 `23127PN0CC`。7 段 v4 试听文件已推送至 `/sdcard/Download/minimal-sleep-loop-previews-v4/`，逐一以 `adb shell sha256sum` 对照本机 `Get-FileHash`，7/7 一致。没有从手机复制录音。
- 现有 versionCode 4 App 经系统文件选择器导入 `rain-01.ogg`，界面显示“正在使用：rain-01.ogg”；`dumpsys media_session` 显示该本地文件 `PLAYING`，位置从约 34.6 秒推进至 40.3 秒。随后暂停，切回内置大雨并在 App 中删除这次导入的副本；UI 无 `rain-01.ogg` 条目，私有导入目录无同大小文件。这个短测只证明该手机能导入与播放 Ogg，未等到 298 秒循环点，也未证明其他四段听感。手机“下载”中的试听文件保留供用户逐段比较。本轮没有构建新 APK。

## 2026-09-22 私有内置雨声试听包

- 用户允许裁剪；原作者、原始链接和可公开再分发授权仍待提供。因此两段 v4 Ogg 仅复制到 Git 忽略的 `app/src/debug/assets/local-sounds/`：`rain-01.ogg` SHA-256 `B1CACE1E59C4248E0E21686543E100AA611A9F8F3875C47757D67FDDD90C9CC9`，`rain-04.ogg` SHA-256 `888FC1071E05DEE973487B93A35B6CBECFBFE61FD0342E53F115A945EDE9A61E`，与 v4 候选一致。`git check-ignore -v` 对两者均指向 `.gitignore` 的 debug 目录规则；原始 MP3 和候选文件未覆盖。
- 新增可选资源目录测试，先运行 `:app:testDebugUnitTest --tests '*LocalPreviewSoundsTest'`，退出码 1，`.tools/local-preview-red.log` 中 `Unresolved reference 'LocalPreviewSounds'`；实现后同命令退出码 0，`.tools/local-preview-green.log`。测试覆盖只显示实际打包的候选、稳定顺序及空目录。完整 `--offline --no-daemon --console plain lintDebug testDebugUnitTest assembleDebug` 退出码 0，`.tools/local-preview-full-build.log` 显示 `BUILD SUCCESSFUL in 46s`；JUnit XML 汇总 16 个测试、0 失败、0 错误。
- `assembleRelease` 退出码 0，`.tools/local-preview-release-check.log` 显示 `BUILD SUCCESSFUL in 1m 43s`。用 Python `zipfile` 检查：debug APK 的 `assets/local-sounds/` 恰有 `rain-01.ogg` 和 `rain-04.ogg`，`app-release-unsigned.apk` 在同路径下没有条目。此 release APK 未签名，不用于安装或发布；目录隔离只证明这次构建未带入两段外来录音。
- 私有 APK `deliverables/minimal-sleep-v0.3.1-local-rain-debug.apk`，59,743,130 字节，SHA-256 `0EA1DB88FCE7829C6F5DD66B500D4E555CADD71309186A65D89A456386760244`；由 `app/build/outputs/apk/debug/app-debug.apk` 不覆盖已有交付文件地复制，复制前后哈希一致。`apksigner verify --verbose` 退出码 0，v2 签名有效。`aapt2 dump permissions` 只列前台服务、麦克风、WAKE_LOCK 与应用内部动态接收器权限，没有 `INTERNET`。
- `adb install -r deliverables/minimal-sleep-v0.3.1-local-rain-debug.apk` 退出码 0，返回 `Success`。手机 `23127PN0CC` 的 `pm path` 找到安装包，`sha256sum` 为 `0ea1db88fce7829c6f5dd66b500d4e555cadd71309186a65d89a456386760244`，与本机一致。第一次启动时屏幕处于锁定状态，未绕过手机密码；2026-09-22 手机已解锁后继续。
- 真机“今晚”页确有“大雨素材试听”“雨雷素材试听”两项，同时原有五种合成声音仍显示。选择前者并点播放后，`dumpsys media_session` 为 `PLAYING`，标题“大雨素材试听”，位置由 0 前进至 11,812 ms；切换后标题变为“雨雷素材试听”，`PLAYING` 位置 2,795 ms，媒体暂停键随后使状态成为 `PAUSED`。这验证该设备能解码两段可选资源并短时播放、切换、暂停；未获得用户对听感的确认，也未等到 298 秒循环点。测试结束已暂停。未复制或上传手机录音，未上传本地素材或 APK。
- 随后选“大雨素材试听”并用 `adb shell cmd media_session dispatch play` 启动一次完整循环，连续以 `adb shell dumpsys media_session` 读取状态：同一标题的 `PLAYING` 位置依次为 59,962、158,357、221,511、279,155 ms；再取样为 17,231 ms 且仍是 `PLAYING`，与 298,000 ms 素材跨过边界相符。最后 `dispatch pause` 后状态为 `PAUSED`、位置 24,896 ms。此检查证明这台手机上大雨素材完成一次功能性循环，**不证明接缝无声学突变**；雨雷素材未做全长循环测试。

## 2026-09-22 内置剪辑与声音排序更新

- 用户明确表示 `rain-01.ogg`、`rain-04.ogg` 对应的原始音轨均由本人录制，授权以 **Resker666** 署名按 CC BY 4.0 修改并公开分发。来源和权利以作者本人声明记录；原始 MP3 名含 B 站视频编号，这些编号本身不作许可依据。原始 MP3、其余五段候选和手机夜间录音都没有纳入仓库。两段 Ogg 从原先忽略的 debug 资源复制到 `app/src/main/assets/local-sounds/`，与 v4 预览 SHA-256 逐一一致。
- 先写 `SoundCatalogSelectionTest` 后执行 `:app:testDebugUnitTest --tests '*SoundCatalogSelectionTest'`，退出码 1，`.tools/sound-selection-red.log` 显示保留声音列表断言失败。移除粉红/棕枚举与 WAV、把两段剪辑置顶并改为默认选择后，`--offline --no-daemon --console plain lintDebug testDebugUnitTest assembleDebug assembleRelease` 退出码 0，`.tools/v040-full-build.log` 显示 `BUILD SUCCESSFUL in 1m 15s`；JUnit XML 汇总 17 个测试、0 失败、0 错误。`python -m unittest discover -s tools -p 'test_*.py' -v` 退出码 0，10 个测试通过。
- 用 Python `zipfile` 与 SHA-256 检查：debug APK 含 `assets/local-sounds/rain-01.ogg`、`rain-04.ogg` 及 `res/raw/heavy_rain.wav`、`ocean_waves.wav`、`white_noise.wav`；release 未签名 APK 含同两段 Ogg 和同三段 WAV（AAPT2 在 release 中重命名 WAV 路径，按文件哈希核对）。两种构建都没有粉红/棕噪声 WAV。两段 Ogg 哈希为 `B1CACE1E59C4248E0E21686543E100AA611A9F8F3875C47757D67FDDD90C9CC9`、`888FC1071E05DEE973487B93A35B6CBECFBFE61FD0342E53F115A945EDE9A61E`。
- 新调试 APK `deliverables/minimal-sleep-v0.4.0-dev-debug.apk`，55,903,025 字节，SHA-256 `ED10F0E43F7D954E231A1718769CFEEE05D5785DBA32B9DCCC04D9FD2F488462`；从构建输出复制时拒绝覆盖同名已有文件，并核对复制前后哈希。`apksigner verify --verbose` 退出码 0，v2 签名有效。`aapt2 dump badging` 为 versionCode 5、versionName `0.4.0-dev`、minSdk 26、targetSdk 35；`aapt2 dump permissions` 未列 `INTERNET`。
- `adb install -r` 退出码 0，手机 `23127PN0CC` 返回 `Success`；已安装 `base.apk` SHA-256 与本机一致。真机“今晚”页依次显示“大雨剪辑”“雨雷剪辑”“合成大雨”“合成海浪”“白噪声”，没有粉红/棕噪声；默认选中大雨剪辑。`dumpsys media_session` 显示大雨剪辑、雨雷剪辑、白噪声先后为 `PLAYING`，切换后最终白噪声为 `PAUSED`。两段剪辑媒体元数据署名 `Resker666 · CC BY 4.0`。这是播放和顺序短测，当前版还未做人耳循环接缝及整夜验收。测试没有复制或上传手机夜间录音，APK 未上传或发布。

## 2026-09-22 GitHub Actions 构建流水线

- 新增 `.github/workflows/android-apk.yml`：`main` 与 `codex/**` 推送触发，安装 JDK 17、Python 3.12、Android SDK API 36、Build Tools 35.0.0 和 FFmpeg；运行 Python 音频工具测试及 Gradle `lintDebug testDebugUnitTest assembleDebug`。仅成功后校验 APK 签名并上传调试 APK 与 SHA-256 文件，保留 14 天。无录音上传步骤、无固定签名密钥或发布 Release 的步骤。
- 本地以 PyYAML `BaseLoader` 解析 YAML，确认 `push`/`workflow_dispatch`、12 个步骤、测试与产物步骤存在，退出码 0。此静态检查不能替代 GitHub Actions 实际运行。
- 本地 `python -m unittest discover -s tools -p 'test_*.py' -v` 退出码 0，10 个测试通过，无跳过。
- 本地复用已有缓存执行 `--offline --no-daemon --console plain lintDebug testDebugUnitTest assembleDebug` 退出码 0，`BUILD SUCCESSFUL in 25s`，58 项 Gradle 任务中 57 项已是最新。此结果验证当前源码与任务组合；不验证云端首次下载或云端产物上传。
- 首次开发分支云端运行 [#1](https://github.com/Resker666/minimal-sleep/actions/runs/35672973981) 在 `Test audio tools` 失败，未执行 Gradle 构建、无 Artifacts；首次合并后的主干运行 [#2](https://github.com/Resker666/minimal-sleep/actions/runs/35673131204) 同样失败。用户提供日志：循环剪辑测试期望 4.5 秒，云端 FFprobe 给出 4.0 秒。诊断运行 [#4](https://github.com/Resker666/minimal-sleep/actions/runs/35673549816) 同时测得 FFprobe 与实际解码均为 4.0 秒，证明音频确实少了 0.5 秒，并非仅容器元数据差异。
- `tools/prepare_loop.py` 将恰好等于过渡时长的 `acrossfade` 输入改为分别淡入、淡出再 `amix`，保留尾首交叉淡化与限幅。现有仓库内 Ogg 素材没有重新生成或覆盖；修复影响之后新制作的剪辑。本地 10 个 Python 测试通过，循环测试测得 FFprobe 与解码均为 4.500 秒。
- 修复后的开发分支云端运行 [#5](https://github.com/Resker666/minimal-sleep/actions/runs/35673768789) 状态 **Success**，总耗时 4 分 45 秒，页面显示 1 个产物 `minimal-sleep-debug-5`（53.2 MB，GitHub 显示的**产物 ZIP** 摘要 `sha256:a371b2929ef0f53351eb3071e7c7a0861ff1c552b412b27673c5a38cc5ff3a65`）。运行已经过 Python 测试、Gradle Lint/单元测试/构建、APK 签名校验和上传步骤。未登录的访问无法下载 ZIP，因此本机尚未独立解压并核对其中 APK；已确认 GitHub 页面显示可下载产物。下载需要登录 GitHub 并有仓库读取权限。
- 合入主干后的云端运行 [#8](https://github.com/Resker666/minimal-sleep/actions/runs/35730491051) 状态 **Success**，总耗时 4 分 25 秒，页面显示 1 个产物 `minimal-sleep-debug-8`（53.2 MB，**产物 ZIP** 摘要 `sha256:95599ee7a07c3dc99ab07b07da2403d6b5f468582c116aaa5efaa5991d044988`）。这验证主干也完成整条工作流；ZIP 内 APK 和 SHA-256 文件仍未在本机独立下载核对。
- 云端调试签名不能假设与当前手机 APK 一致；固定签名按用户要求留待以后。工作流只上传构建的 APK 与校验文件，没有上传手机录音。

## 2026-09-23 iOS GitHub Actions 第一阶段

- 新增 `.github/workflows/ios-build.yml`：`main`、`codex/**` 推送、相关 Pull Request 和手动触发可运行。工作流只授予 `contents: read`，动态选取可用 iPhone 模拟器，执行 XCTest，并以禁用代码签名的 Release 配置生成 `MinimalSleep-iOS-Simulator.zip` 与 SHA-256 文件；产物保留 14 天。没有写入 Apple ID、Personal Team、证书、描述文件或 Team ID。
- 本机 Xcode 27.0 基线执行 `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` 退出码 0，结果为 **31 个测试、0 失败**，末尾为 `** TEST SUCCEEDED **`。
- 本机执行与工作流等价的无签名 Release 模拟器构建，退出码 0，末尾为 `** BUILD SUCCEEDED **`。`MinimalSleep.app` 主可执行文件存在且非空；最终提交前重新从全新构建目录用 `ditto` 打包，临时 ZIP 的 SHA-256 为 `1aefabcf371e3a110fc7984691984e1d3ad4aaad17050b8bc1ec5c74a78c1084`。临时包位于 `/tmp`，不进入 Git。
- Ruby 标准库成功解析工作流 YAML 并识别 8 个步骤；静态检查确认 macOS 26、禁用签名、Artifact 上传、14 天保留和 SHA-256 步骤存在，且工作流文本没有 `DEVELOPMENT_TEAM` 或开发证书信息。本机缺少 PyYAML，因此没有安装额外依赖。
- 首次开发分支云端运行 [#1](https://github.com/Resker666/minimal-sleep/actions/runs/35852288923) 状态 **Success**，总耗时约 8 分钟。环境检查、动态模拟器选择、XCTest、无签名 Release 构建、打包校验、上传和下载链接步骤全部为 `success`。页面生成 1 个产物 `minimal-sleep-ios-simulator-1`，大小 98,676,086 字节，GitHub Artifact 摘要为 `sha256:81c6f25f02252560000a7852b480c4cf494d3a899c64f51730a25d44b1f7c957`，到期时间为 2026-10-07 19:11（UTC+8）。此摘要对应 GitHub 外层 Artifact ZIP；尚未登录下载并独立解压核对其中的 App ZIP 与内部 SHA-256 文件。

## 2026-09-24 iOS 生成音频本机验证

- 环境：macOS 27.0 (`26A428`)、Xcode 27.0 (`27A266a`)、Apple Python 3.9.6、Homebrew FFmpeg 9.0.2、iPhone 18 Pro / iOS 27.0 模拟器 `75FA9690-7229-4F85-96C1-284AD9262383`；验证时提交 `3e2e902ba59e`。
- `python3 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v` 退出码 0，4 个测试通过。
- `python3 tools/prepare_ios_audio.py --ffmpeg "$(command -v ffmpeg)"` 退出码 0；`rain-01.wav` 与 `rain-04.wav` 的 SHA-256 分别为 `bdfda7d0dec01eaf65eb006bc2f09d1276ec11ac601120d28e7797c35e958269` 和 `3f66e5b609802376af96221911f50d474ef42239b449c80c22c911c742a5b8dc`。两个文件被 Git 忽略且未跟踪，两个派生清单无 diff。
- iPhone 18 Pro 模拟器 Debug XCTest 退出码 0：31 个测试、0 失败，末尾 `** TEST SUCCEEDED **`。禁用签名的 Release 模拟器构建退出码 0，末尾 `** BUILD SUCCEEDED **`；App 主可执行文件和五个 WAV 均存在且非空。
- 本节没有记录新的 GitHub Actions 通过，也没有记录真机通过。真机发声、循环听感、锁屏定时、后台持续播放、路由中断、导入、数据保留、飞行模式与 8 小时整夜播放均为未测。

## 2026-09-24 iOS 生成音频云端验证

- 首次 [iOS 运行 #6](https://github.com/Resker666/minimal-sleep/actions/runs/35958149518) 使用 Homebrew FFmpeg 9.0.1_1；音频测试和转码成功，但两个 PCM 哈希与本机 FFmpeg 9.0.2 的已审阅清单不同，严格清单 diff 按设计失败，后续 XCTest、构建和上传均未运行。
- 提交 `a9d4c7e5089c` 在 `brew install` 前执行 `brew update`，并加入 FFmpeg 9.0.2 版本门禁。修复后的 [iOS 运行 #7](https://github.com/Resker666/minimal-sleep/actions/runs/35958729555) 状态 Success，总耗时 5 分 44 秒；Python 3.12、FFmpeg、音频生成与清单、模拟器 XCTest、无签名 Release 构建、五资源打包检查和 Artifact 上传均为 success。
- Artifact `minimal-sleep-ios-simulator-7`：98,676,086 字节（GitHub 页面 94.1 MB），外层摘要 `sha256:90281f002c7e4f4bedef08fb837d2f369ded5f2bd358259114acfb9be0ce302d`。登录下载并自动解开外层 ZIP 后，内部 App ZIP 为 98,675,644 字节；实算 SHA-256 `6ffcce703d221ed8d17d87ca8eacae8391fbea8edc01f412d09317106aa33fb1`，与随包 `.sha256` 一致。
- 云端产物仍是未签名 iOS Simulator App，不能安装到 iPhone；本节不代表任何真机项目通过。
