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
- 最终复查提交 `9f9e9a17bac43b206e25c78a8602b62450feff12` 补上 `.gitignore` 路径触发、反向忽略规则拒绝和便携校验文件名。[iOS 运行 #8](https://github.com/Resker666/minimal-sleep/actions/runs/35960026403) 状态 Success，总耗时 6 分 58 秒；全部构建及收尾步骤均为 success。Artifact `minimal-sleep-ios-simulator-8` 为 98,676,081 字节，外层摘要 `sha256:54a1ddf2c83a6a9cd92b026e72a9a2e8ccc4e9b09c847f593139e562b3fd4271`，到期时间 2026-10-08 05:34:21 UTC。CI 打包步骤已直接执行随包 SHA-256 校验并成功；本机尚未独立下载运行 #8 产物。
- 云端产物仍是未签名 iOS Simulator App，不能安装到 iPhone；本节不代表任何真机项目通过。

## 2026-09-24 iOS AAC/M4A 压缩本机验证

- 两段 Android Ogg 保持 298 秒且不改动。iOS 派生格式由 16-bit PCM WAV 改为 128 kbps AAC/M4A，不再次裁剪、调整增益、改变声道或重采样。
- `rain-01.m4a` 为 4,834,016 字节，SHA-256 `ea9a392d6e262d19db2c9ef8c1bb31ce81db2ecc420d11fd474217e7d15594fc`；`rain-04.m4a` 为 4,859,928 字节，SHA-256 `b779392b3ff4c7a24d2459477c4d8e28969cb123e1989c507942266e385ca85b`。两者均为 298 秒、AAC、44.1 kHz、双声道，并低于脚本的 6,500,000 字节单文件上限。
- Homebrew Python 3.12.14 下 6 个 iOS 音频准备测试通过；在全新临时目录重新生成后，两个 M4A 和两份派生清单与工作区结果逐字节一致。
- iPhone 18 Pro / iOS 27.0 模拟器执行 33 个 XCTest，0 失败；测试确认两个 M4A 可从主 Bundle 查找、可由 AVAudioPlayer 加载且时长为 298 秒。Release 模拟器构建成功，App 中有两段 M4A 和三段 WAV，旧雨声 WAV 不存在；App 目录约 18 MB，本机打包 ZIP 约 17 MB。
- [iOS 云端运行 #9](https://github.com/Resker666/minimal-sleep/actions/runs/35965815562) 在提交 `ebdc0da253b3` 上状态 Success，总耗时 7 分 39 秒；音频工具测试、M4A 生成与严格清单校验、33 个 XCTest、无签名 Release 构建、包内资源检查和上传全部为 success。Artifact `minimal-sleep-ios-simulator-9` 为 17,463,485 字节，外层摘要 `sha256:307068595dbe1ba0d0ac5d3dcf382482bf9369f13b026a33844029727312d9cf`，到期时间 2026-10-08 06:50:11 UTC；比 PCM 运行 #8 的 98,676,081 字节减少约 82.3%。
- 同一提交的 [Android 云端运行 #26](https://github.com/Resker666/minimal-sleep/actions/runs/35965815557) 状态 Success；音频工具测试、Lint、JVM 单元测试、Debug APK 构建、校验和上传均通过，Android Ogg 资源未改动。
- 本机使用 Personal Team 的通用 iPhone Debug 构建成功，`codesign --verify --deep --strict` 通过；设备当时已断开，因此未安装或启动。AAC 循环边界、真实扬声器听感、锁屏持续播放和整夜可靠性仍需真机验证。

## 2026-09-24 Android 三晚会话元数据排查

- 用户报告三晚长时间采集未中断，但后两晚各只能看到一个片段；用户确认手机位置和朝向与最早一晚基本相同。通过已连接的 `23127PN0CC`、本机 `D:\soft\platform-tools\adb.exe`（ADB 36.0.0）读取 App 私有 Room 数据库的**元数据**：分别用 `adb exec-out run-as io.github.resker666.minimalsleep cat` 读取 `minimal-sleep.db`、`minimal-sleep.db-wal`、`minimal-sleep.db-shm`，Python 临时目录只用于 SQLite 查询，会随进程结束删除；没有读取、复制或上传任何 WAV 录音。手机当前安装 versionCode 5 / `0.4.0-dev`，最近更新时间 2026-09-22 08:19:27；不能据此断定更早会话的安装版本。
- 2026-09-20 23:59:06–09-21 07:45:53：有效采集 28,006.3 秒，`COMPLETED`、无中断记录，18 个片段，最后片段起点在采集后 27,992.6 秒。片段均为 `LEGACY`，当时尚无自动分类；助眠海浪播放 284.9 秒。
- 2026-09-21 23:54:00–09-22 07:50:06：有效采集 28,565.9 秒，`COMPLETED`、无中断记录，仅 1 个片段，起点 0 秒、时长 18.8 秒；`READY` / `未确定`，无模型来源标签或分数，播放干扰标记为真；雨雷剪辑播放 887.4 秒。该会话发生在当前 APK 最近更新时间之前。
- 2026-09-23 00:11:12–07:34:01：有效采集 26,569.2 秒，`COMPLETED`、无中断记录，仅 1 个片段，起点 0 秒、时长 13.3 秒；`READY` / `未确定`，无模型来源标签或分数，播放干扰标记为真；大雨剪辑播放 893.6 秒。
- 数据库共 6 个会话、40 个片段；手机应用私有录音目录列出 40 个文件。后两晚分类任务没有失败或排队跳过，主要现象是开头片段之后**没有新片段提交给模型**。`COMPLETED` 和采集样本数证明读循环走完，不能证明整个夜晚的麦克风信号有足够音量，也不能证明没有鼾声或人声。现有记录不保存未触发时段的 RMS / 峰值统计，故目前不能区分输入过低、遮挡、设备静音与能量阈值不合适；这需要只在设备上进行受控声音测试或增加不含原音的诊断统计。尚未修改触发阈值或分类规则，也未声称准确率改善。

## 2026-09-25 Android 受控复现、时间轴与采集诊断

- 真机 `23127PN0CC`、Android API 36、原 App versionCode 5 / `0.4.0-dev`。用户允许 3 分钟纯录音及约 5 分钟锁屏雨声复现。第一次 07:55:24–07:58:36，`COMPLETED`、192 秒、10 片段、0 中断、无播放；片段起点从 12.4 到 183.8 秒。第二次 08:00:37–08:06:07，`COMPLETED`、330 秒、16 片段、0 中断；雨雷声播放区间 0–74.4 秒，第一个片段有播放干扰，其余 15 个片段无干扰且最晚起点约 283 秒。手机锁屏/Dozing 后暂停雨声，短时录音和触发仍可工作。未读取或复制任一 WAV；检查限于数据库元数据。此短测不代表整夜识别可靠。
- 原有 40 个录音文件，加上述 10 和 16 个新片段，`adb shell run-as io.github.resker666.minimalsleep ls files/recordings` 用 PowerShell `Measure-Object -Line` 实测 **66** 个文件。原 App 仍为 versionCode 5，未卸载或清除数据。
- 本轮开始时 `.tools/jdk/jdk17.0.20_10`、`.tools/android-sdk-ready`、`.tools/gradle/gradle-8.13`、`.tools/gradle-home` 均不存在，系统 PATH 无 Java/Gradle；按已有开发说明检查后才下载并恢复到这四个忽略路径。下载归档按之前记录的散列核对，未把工具和缓存加入 Git。随后复用缓存执行 `--offline --no-daemon --console plain -Pkotlin.compiler.execution.strategy=in-process lintDebug testDebugUnitTest assembleDebug`，标准包 `BUILD SUCCESSFUL in 49s`，试用后缀包 `BUILD SUCCESSFUL in 44s`，均 58 个 Gradle 任务；JUnit XML 汇总 **24 tests / 0 failures / 0 errors**。测试先以未实现符号出现预期失败，随后新时间轴与灵敏度/统计测试通过。
- 标准包 `deliverables/minimal-sleep-v0.5.0-dev-debug.apk`：55,854,571 字节，SHA-256 `2694237CC66429E7927B712D9417DEDDD170B848B15DF00130113B89E77D80EE`，包名 `io.github.resker666.minimalsleep`，versionCode 6、versionName `0.5.0-dev`，minSdk 26、targetSdk 35。试用包 `deliverables/minimal-sleep-v0.5.0-dev-trial-debug.apk`：55,854,595 字节，SHA-256 `BA5B0BEF9F43470BA6D76A4695287092AD381EAA1D824A437DC793FC46D6F114`，包名加 `.trial`，versionName `0.5.0-dev-trial`。两个包的 `apksigner verify --verbose` 均显示 v2 签名有效；`aapt2 dump permissions` 未列 `INTERNET`。原手机 APK、标准包和试用包经 `apksigner --print-certs` 重新核对证书 SHA-256 都是 `645b0dbc952ac939815d8754cd4ebac07d38e53f25759c331368417a49cc7a2f`，标准包可安全尝试覆盖安装。此前一次签名不匹配判断已被直接复核纠正。
- 用已导出的 Room v2 schema 构造**合成**数据库（1 个合成会话和 1 个元数据片段，不含任何真实录音），`PRAGMA user_version=2`；本机 SQL 检查确认迁移后原两行存在，`capture_hours` 10 列与生成的 v3 schema 一致。首次 `adb install -r` 试用包返回 `INSTALL_FAILED_USER_RESTRICTED`；用户允许 USB 安装后重试返回 `Success`。把合成旧库放入独立试用包，打开记录页可见原合成会话和片段，关闭后只读取该**合成**私有数据库核对 `PRAGMA user_version=3`、原两行仍在、`capture_hours` 表可查询。没有对真实旧库注入数据。
- 清除试用包的合成数据后，新建 91 秒短录音：`COMPLETED`、3 个片段/事件组、雨声播放区间 37 秒，首片段显示播放干扰；“采集音量诊断”显示高灵敏度、第 1 小时低于最低门槛 32%、触发帧 407、最大 RMS 0.124。模型对无播放干扰片段出现“人声/疑似梦话”候选，未用真实标注判断正误；不能声称分类变准。时间轴拖到无保存片段区间时显示“这个时间没有保存录音”及上一/下一片段，片段内拖动后 UI 显示播放位置 11/15 秒。短测结束停止播放；试用包中产生的 3 个测试片段未复制到电脑。
- `adb install -r deliverables/minimal-sleep-v0.5.0-dev-debug.apk` 覆盖原 App 返回 `Success`；`dumpsys package` 为 versionCode 6 / `0.5.0-dev`，手机 `base.apk` SHA-256 与本地标准包一致。真实旧记录页正常打开 2026-09-23 00:11 的 26,569 秒/1 片段会话，显示 893 秒助眠声播放；时间轴从 00:11 到 07:34，拖到约 03:47 提示该时段没有保存录音。`run-as` 列目录计数在更新前后均为 **66** 个 WAV 文件。独立试用包完成测试后已卸载，手机只保留正式包。真实旧库的 Room 迁移与展示因此经真机验证；未读取或复制用户 WAV。尚缺按同一放置方式的整夜高灵敏度对照、逐小时统计和真实标注样本的误报/漏报评估。


## 2026-09-27 Android 界面 A 方案

- 用户选择 A：浅灰/深灰分组卡片、蓝色操作、系统字体、今晚/记录双页。分支 `codex/android-minimal-ui` 从 `416c6aa` 建立。改动限 Android Compose、Android 版本号及相关说明；未改 iOS 工程、Room schema、录音与分类算法、音频资源。界面结构和手工用例见 [android-ui.md](android-ui.md)。
- 本机 `.tools/jdk/jdk17.0.20_10`、`.tools/android-sdk-ready`、`.tools/gradle/gradle-8.13`、`.tools/gradle-home` 均已存在，直接复用；本轮没有下载环境或添加依赖。命令：`gradle.bat --offline --no-daemon --console plain -Pkotlin.compiler.execution.strategy=in-process lintDebug testDebugUnitTest assembleDebug`。最终退出码 0，`BUILD SUCCESSFUL in 53s`，58 个任务（16 executed / 42 up-to-date）。JUnit XML 汇总 **24 tests / 0 failures / 0 errors / 0 skipped**；Lint **0 errors / 10 warnings**，包括既有 targetSdk、导出媒体服务、Kapt、存储及 KTX 建议。仅界面排列/样式与偏好改动，未新增复刻实现的测试；尚不能以编译替代 UI 验收。
- 最终 APK：`deliverables/minimal-sleep-v0.6.0-dev-debug.apk`，55,920,107 字节，SHA-256 `64F35D3AB31953EE5911975E9843AE37B9FFCF6BF2270394D7DAC20068E82234`；同目录有 `.apk.sha256` 文件。包名 `io.github.resker666.minimalsleep`，versionCode 7 / `0.6.0-dev`，minSdk 26、targetSdk 35。`apksigner verify --verbose --print-certs` 验证 v2 签名有效；证书 SHA-256 `645b0dbc952ac939815d8754cd4ebac07d38e53f25759c331368417a49cc7a2f`，沿用本机调试签名。`aapt2 dump permissions` 未列 `INTERNET`。
- 连接设备 `e2f1a08` / `23127PN0CC`，最终 APK `adb install -r` 返回 `Success`；`dumpsys package` 显示 code 7 / `0.6.0-dev`。安装前后只用 `run-as ... ls files/recordings` 计数，均为 **37** 个文件；未读取、复制或上传 WAV，未卸载原 App、未清除数据、未新增或删除录音。本轮 37 与 9 月 25 日历史记录的 66 是不同时点的实测，不把二者差额归因于本次升级。
- 尝试启动 Activity，设备要求密码/指纹解锁。`wm dismiss-keyguard` 不能解锁受保护锁屏，UI dump 仍显示密码锁屏；已向用户请求手动解锁。没有尝试绕过密码，未把黑色锁屏截图当成 App UI 证据。**新版页面外观、浅/深/系统主题、弹层、偏好重启保持、大字体、导入及录音/回听回归尚未执行。**
- 独立只读代码审查未发现本次引入的严重或重要问题；已将回声说明明确为“干扰标记不代表回声消除”，并为开关及进度条加入无障碍标签。审查不代替真机视觉和操作验证。
- 未推送或公开发布本轮 APK。整夜可靠性、识别准确率、固定云端签名及既有 M3–M5 待办仍未完成；本次 UI 更新不能证明这些项目通过。
- 后续用户反馈“看着可以，验证通过”：记录为 **用户确认新版 UI 验收通过**，证据来源为用户反馈。前述代理受锁屏限制的记录保留；未收到浅/深主题、大字体、导入、回听等逐项结果，不据此补记这些专项测试或整夜识别验收通过。
- 用户随后授权推送并合入主干。提交前重新运行离线 `lintDebug testDebugUnitTest assembleDebug`：退出码 0、25 秒，58 个任务（1 executed / 57 up-to-date）；输入未变，JUnit/Lint 使用既有有效结果。重新运行 `python -m unittest discover -s tools -p 'test_*.py' -v`：16 tests、3.501 秒、OK。已获取最新 `origin/main`，仍为 `cb950c3`，待集成范围包含 `416c6aa` 录音/时间轴提交及本轮 UI；未改 iOS 文件。云端检查和最终合并状态以对应 PR / Actions 为准。

## 2026-10-04 排查 10 月 1 日夜间“进程中断”

- 用户连接真机 `23127PN0CC` / API 36，请求分析 10 月 1 日采集中断。Git 工作区起始干净，当前 `main`；手机仍为 versionCode 7 / `0.6.0-dev`，最后 App 更新为 2026-09-27 22:13:12。本轮没有安装、停止进程、启动录音、修改手机设置或读取音频原音。
- 用 `adb exec-out run-as ... cat databases/minimal-sleep.db` 与 `-wal` 获取**仅数据库元数据**，在系统临时目录中读只读快照，分析后自动清除临时文件；未放入仓库。两次读取字节一致，SQLite `quick_check=ok`。查询结果：会话开始 **2026-10-01 22:04:25.501 +08:00**，状态 `INTERRUPTED`，原因“进程中断”，`endedAtEpochMs` 为 **2026-10-02 07:46:28.328**，但 `durationSamples=0`。
- 该会话已提交 **225 个片段**，累计片段音频 1,636.352 秒（约 27 分 16 秒），225 条分类状态均为 `READY`，不能据此判断分类正误。最后片段结束于采集样本位置 **13,554.176 秒（3 小时 45 分 54.176 秒）**，按会话时间轴换算为 **10 月 2 日约 01:50:19.677**。这个换算按样本时钟，不是精准的进程死亡墙钟时间。已落库的每小时统计有第 1–3 小时，各 56,250 帧，说明至少完成这些小时的采集；第 4 小时没有正常收尾统计。助眠声区间 0–898.624 秒（约 14 分 59 秒），2 个片段标记播放干扰；没有 `recording_gaps` 行。全库片段与私有 WAV 文件数量均为本轮实测 **276**，未删除或复制 WAV。
- **设备重启证据**：`/proc/stat` 的 `btime=1790877730` 换算为 **2026-10-02 02:02:10 +08:00**。`ro.boot.bootreason` 与 `sys.boot.reason` 都是 `reboot,ota`，`sys.boot.reason.last` 为 `reboot,update,system-update`。`persist.sys.boot.reason.history` 包含 `reboot,update,system-update,1790877744`（02:02:24）及 `reboot,ota,1790877788`（02:03:08）；后两者是启动原因历史写入时间，不能当作录音精确终止时刻。当前系统为 `OS3.0.306.0.WNCCNXM`。DropBox `SYSTEM_BOOT` 条目于 07:46:32 写入、带 `isPrevious: true`；这个条目时间不能替代内核开机时间。依据这些直接证据，**系统更新引起的手机重启，是该夜采集被打断的最有力解释**。未核实是夜间自动更新还是用户安排的更新重启。
- `dumpsys activity exit-info` 留存了多次 `LockScreenClean` / `FORCE STOP`，但邻近本夜的两条分别是 10 月 1 日 **16:47:53**（会话开始前）和 10 月 2 日 **07:59:51**（已补记中断之后）。不能拿它们证明该夜凌晨是锁屏清理杀进程。留存退出记录及当前 crash buffer 未看到与本夜凌晨匹配的 Java crash / ANR；历史缓冲有限，这不是永不崩溃的证明。
- **App 中断恢复的已确认缺口**：`SleepDao.markStaleInterrupted(now)` 将仍为 `RECORDING` 的会话标成中断，并把 `endedAtEpochMs` 写成下次查看记录/开始新录音的时间，没有恢复 `durationSamples`。`RecordingService` 的采集游标只在内存中更新，正常 `finally` 才保存总时长；手机重启时无法依赖这个收尾。因此 UI 会显示有效采集 0 秒，整夜时间轴也因总时长为 0 不可拖动，即使此前 225 个片段已经保存。这是元数据恢复问题，不代表整晚没有采集。
- 参考依据：[AOSP 启动原因说明](https://source.android.com/docs/core/architecture/bootloader/boot-reason)、[AOSP bootstat 实现](https://android.googlesource.com/platform/system/core/+/master/bootstat/bootstat.cpp)（`reboot,ota` 和历史时间写入）、[ApplicationExitInfo 文档](https://developer.android.com/reference/android/app/ApplicationExitInfo)。启动属性来自本机实测，文档用于解释属性和退出原因语义。
- 本轮只完成取证与分析，未修改产品代码、用户数据库或设置，未做重启复现，未生成新 APK。待补：定期持久化采集进度/心跳、记录开机标识与恢复时间、把未知结束时间与真实采集时长区分，恢复已保存片段的可用时间轴。手机整体更新/重启期间无法保持连续录音，不能承诺补回未保存原音。

## 2026-10-04 Android 中断恢复与自定义定时

- 在 `codex/android-recovery-timer` 实现中断恢复和 1–720 分钟整数定时，增加 5 分钟快捷项；原有白噪声、雨声/海浪、离线约束、播放干扰标记及 10 秒淡出保留。只修改 Android 代码及相关文档，不修改 iOS、模型、音频素材或许可。
- 新回归用例先因恢复符号未实现而编译失败；随后用原有“时长不恢复、发现时间充当结束时间”的行为重现症状，定时保持旧白名单。`.tools/recovery-timer-red-behavior.log` 为 **11 tests / 7 failed**：5 个恢复用例和 2 个短时/自定义定时用例按预期失败，其余旧计时用例通过。实现后运行完整 Android 命令，未只跑新增用例。
- 沿用已有 `.tools/jdk/jdk17.0.20_10`、SDK、Gradle 8.13 与缓存，无下载或新依赖。命令 `gradle.bat --offline --no-daemon --console plain -Pkotlin.compiler.execution.strategy=in-process lintDebug testDebugUnitTest assembleDebug` 退出码 0，`.tools/recovery-timer-green.log` 为 **BUILD SUCCESSFUL in 1m 20s**，58 个任务（27 executed / 31 up-to-date）。JUnit XML 汇总 **31 tests / 0 failures / 0 errors / 0 skipped**，Lint XML **0 errors / 9 warnings**。独立试用后缀包 `-PminimalSleepTrial=true assembleDebug` 退出码 0，26 秒，40 个任务。构建保留既有平台工具及 Kapt 提示；实际 ADB 使用另行安装的 `D:\soft\platform-tools\adb.exe`。
- `python -m unittest discover -s tools -p 'test_*.py' -v` 退出码 0，**16 tests / OK**，3.128 秒；未改动音频工具。本机 SQLite 检查用受控合成 v3 数据库运行实际 v3→v4 SQL：原 4 个会话和 1 个合成片段保留、3 个新字段为 NULL、全部 5 张表的列与 Room v4 导出一致；实际 checkpoint SQL 保持样本数单调增加且不更新已完成会话。旧 schema v3 与 HEAD 内容一致，仅新增 v4 schema。此检查不能替代 Android 上 Room 的实际迁移验收。
- 标准 APK `deliverables/minimal-sleep-v0.6.1-dev-debug.apk`：**55,936,491 字节**，SHA-256 **E1216A81333298D5ED4F1548EE7B643694248A585A578F9B2A00CBA3183192E9**；同目录有 `.apk.sha256`。包名 `io.github.resker666.minimalsleep`、versionCode **8** / versionName **0.6.1-dev**、minSdk 26 / targetSdk 35。`apksigner verify --verbose --print-certs` 验证 v2 签名有效，证书 SHA-256 `645b0dbc952ac939815d8754cd4ebac07d38e53f25759c331368417a49cc7a2f`，沿用当前本机调试签名；`aapt2 dump permissions` 未列 `INTERNET`。APK、构建工具、设备元数据与测试夹具均不纳入 Git。
- 升级前读取**仅数据库元数据**的两次一致快照，SQLite `quick_check=ok`、schema v3；5 个会话、276 个片段、4 个播放区间、20 个小时统计，私有 WAV 目录计数 276。事件元数据 SHA-256 `9e7e639411526e472715a285fedcfb84a8d6c98b3ae208b240d28ca723f1bf82`，用于核对升级是否保留标签/文件引用/干扰标记；未读取 WAV。临时元数据快照在只读查询后清除；首次 Python SQLite 连接没有显式关闭导致临时目录清理失败，已修正为显式关闭，删除该临时目录并确认不存在；再次读取和清理成功，没有在仓库保存快照。
- `adb install` 独立试用包返回 **INSTALL_FAILED_USER_RESTRICTED: Install canceled by user**，已向用户请求允许本次 USB 安装。此时尚未安装标准更新、未强制停止正式 App、未启动录音、未改手机设置。真实 Room 迁移、旧夜恢复、5/6 分钟 UI、实际到期和受控异常恢复均待后续安装后验证。
- 独立只读代码审查未发现 P1/P2 问题，核对了迁移、事务生成、恢复入口的服务状态检查、稳定区间 ID 和定时输入校验；审查没有操作手机，不能当作真机通过。
- API 依据：[Android BOOT_COUNT](https://developer.android.com/reference/android/provider/Settings.Global#BOOT_COUNT)、[Room 迁移说明](https://developer.android.com/training/data-storage/room/migrating-db-versions)。保存启动次数无需网络权限；次数变化只用于提示设备曾重启，App 不声称能识别 OTA 根因。采集检查点是已确认进度，可能落后真实读帧；原音依然只保存触发片段，未提交缓冲内容和重启期间声音不能恢复。

### 允许安装后的真机续验

- 用户确认安装后，`adb install -r deliverables/minimal-sleep-v0.6.1-dev-trial-debug.apk` 返回 **Success**；独立包 code 8 / `0.6.1-dev-trial`，`firstInstallTime=2026-10-04 15:54:52`。首次打开前确认其 `databases` 目录不存在，才注入仅含合成元数据的 v3 夹具；使用不覆盖已有数据库的写入保护，没有向正式包注入夹具或操作正式录音。
- 打开试用包记录页，实际 Room 迁移到 v4，`quick_check=ok`，原 4 个会话、1 个合成片段、1 个播放区间、1 个小时统计均保留。完成会话仍为 40 秒 / `COMPLETED`；旧版中断会话从 0 恢复为 **216,866,816 样本（13,554.176 秒）**，`endedAtEpochMs=NULL`、原误记结束时间移入恢复时间；未结束会话按已保存区间/小时起点恢复，无证据的会话仍显示未知。这里没有合成音频文件，不把夹具的回听尝试当作真实回听证据。
- 定时面板可见“5 分钟”快捷项和自定义输入；输入 **6** 并应用后，今晚页实测显示“6 分钟后停止”。随后选择 5 分钟并开始记录，授予独立包麦克风权限，界面显示“剩余约 5 分钟”且“正在记录”。锁屏后 `dumpsys power` 为 `Dozing`。采集约 30 秒与 100 秒时，元数据仍为 `RECORDING`，样本进度 **480,256→1,605,632**；同一播放区间 ID 的结束样本同步增加，部分小时统计 **469→1,568 帧**，证明锁屏期间检查点实际写入；原音仅保存在独立包私有目录，未复制到电脑。
- **5 分钟实际到期**：到期后媒体状态由 `PLAYING(3)` 变为 `PAUSED(2)`，今晚页显示“定时已结束”，录音仍为 `RECORDING`；采集进度 **5,136,384 样本（321.024 秒）**，已关闭的播放区间为 **0–4,796,416 样本（299.776 秒）**。这是一次锁屏实测；样本区间长度受播放/采集启动时间差影响，不把它当作绝对墙钟计时精度测量。实际淡出听感未由用户确认。随后重新设 6 分钟并播放，UI 显示“剩余约 6 分钟”，本次没有等待 6 分钟完整到期。
- **突然退出恢复**：只取得独立试用包的单一 PID，使用同 UID 的 `run-as ... kill -9` 终止；留存退出信息为 **16:04:53.032 / SIGNALED / status=9**，未对正式包执行终止。重开试用包后，该测试会话从 `RECORDING` 恢复为 `INTERRUPTED`；**6,421,504 样本（401.344 秒）**、末次进度时间 **16:04:48.114**、5 个实测片段、2 个播放区间及 6,271 帧部分小时统计保留，确切结束时间为 NULL、发现中断时间单独记录。同 UID 未重启，启动计数仍为 28，显示进程中断而未误报重启。事件、区间与小时统计的元数据摘要在终止前与恢复后完全一致；私有 WAV 均为 5。进程突然退出测试不代表已复现整机 OTA 重启。
- 恢复后的试用包详情显示“至少 6 分 41 秒 / 5 个片段”，整夜时间轴启用；拖到约 16:01 的空白区显示“这个时间没有保存录音，可选择附近片段”，没有填充不存在的原音。本次没有声称片段回听或标签准确率通过。
- **正式更新**：`adb install -r deliverables/minimal-sleep-v0.6.1-dev-debug.apk` 返回 **Success**；手机为 code 8 / `0.6.1-dev`，更新时间 **16:08:03**，`sha256sum` 安装的 `base.apk` 得到 `e1216a81333298d5ed4f1548ee7b643694248a585a578f9b2a00cba3183192e9`，与本机一致。打开真实记录页后实际 Room schema **v4 / quick_check=ok**，5 个会话、276 个事件、4 个播放区间、20 个小时统计和 **276 个私有 WAV** 全部保留。事件摘要仍为 `9e7e639411526e472715a285fedcfb84a8d6c98b3ae208b240d28ca723f1bf82`，区间和小时统计摘要也与升级前一致。
- 10 月 1 日旧会话实际恢复为 **216,866,816 样本（13,554.176 秒）**，详情显示“至少 3 小时 45 分 / 225 个片段”；时间轴为 **10-01 22:04–10-02 01:50** 且启用。原误记的 **10-02 07:46:28.328** 移为 `recoveredAtEpochMs`，`endedAtEpochMs=NULL`，旧会话没有启动计数和末次读帧时间，未凭分析结论伪造这些字段。正式旧音频未回听、删除、读取或复制到电脑。
- 卸载本次新装的独立试用包返回 **Success**，清理的是本次合成夹具和 5 个测试 WAV；正式包保留。真机 6 分钟完整到期、实际淡出听感、8 小时受控整夜和整机重启复现仍待验，不以短测、代码审查或成功构建代替验收。
- 用户随后确认“好，验证通过推送到远端吧”，记录为 **用户验收当前 v0.6.1-dev 通过**并授权推送源码。没有收到整夜测试、6 分钟完整到期或整机 OTA 重启的专项结果，上述待验项目仍保留。
- 源码推送前复验：同一离线命令 `lintDebug testDebugUnitTest assembleDebug` 退出码 0，`.tools/recovery-timer-prepush.log` 为 **BUILD SUCCESSFUL in 44s**，58 个任务（10 executed / 48 up-to-date）；单元测试及 Lint 沿用输入未变的缓存结果，当前报告仍为 **31 tests / 0 failures / 0 errors / 0 skipped**、**0 lint errors / 9 warnings**。音频工具测试重新执行为 **16 tests / OK**（3.216 秒），`git diff --check` 通过。此次复验未重新安装手机、下载工具或发布 APK。
