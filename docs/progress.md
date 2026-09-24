# 开发进度

更新：2026-09-24。当前音频处理分支 `codex/loop-audio-previews` 从 `codex/continue-m3-m5` 建立；公开预发布仍是 `v0.2.0-preview.1`，本轮新包尚未公开发布。

| 阶段 | 状态 | 说明 |
|---|---|---|
| M0 | 已完成 | Kotlin + Compose 工程、许可证、构建工具链、签名 APK 与 Android API 36 真机启动。 |
| M1 | 可运行；音频主观质量与长时播放待验 | 当前内置两段 Resker666 雨声剪辑、白噪声、合成大雨与合成海浪，已移除粉红/棕噪声。两段剪辑在页面最前并可短时播放；大雨剪辑在此前私有调试版完成一次功能性循环，当前 0.4.0-dev 的主观接缝与整夜播放待验。系统选择器导入、私有目录复制、播放及删除已在真机验证。15/30/60/90 分钟、整晚与 10 秒淡出已实现；实际到期、耳机拔出和音频焦点仍需测。 |
| M2 | 30 分钟锁屏试录通过；整夜可靠性待验 | 唯一 AudioRecord、能量片段、WAV/Room、回听、播放区间、干扰标记。2026-09-21 真机仅录音锁屏后有效采集 1,918 秒，状态 `COMPLETED`，18 个片段/事件组，记录页无中断缺口。此前另有 28,006 秒 `COMPLETED` 会话，条件不明，不计作受控整夜验收。USB 充电期间电量 19%→25%，不能推断耗电。 |
| M3 | 本地推理闭环已跑通；准确率未验 | 固定 Google YAMNet Lite v1 权重、521 标签、Apache-2.0 来源与 SHA-256；LiteRT 1.4.2，采集后有界队列推理，Room v1→v2 保留旧记录，模型版本/分数/手动标签可见。真机模型实际加载并产生结果。合成海浪播放时曾误判 `Speech 0.59`，现将受播放干扰的疑似人声、鼾声、咳嗽按“未确定”显示/统计，保留原模型结果。合法真实样本的误报/漏报与阈值验证未完成。 |
| M4 | 部分可运行，整体未完成 | 播放区间、重叠干扰标记、并集播放时长及干扰内外事件组计数已实现；缺 NightSessionCoordinator、持续背景声摘要、7/30 次趋势、白噪声与人声/鼾声对照、跨午夜及音频路由真机验证。 |
| M5 | 部分隐私措施已做，整体未完成 | 禁止云备份、无网络权限、初步录音空间上限，手动删除录音与导入音频已做。音频保留期、收藏保护、用户主动导出、完整容量策略、8 小时受控整夜及异常恢复验收未完成。 |

当前本地可安装 APK：`deliverables/minimal-sleep-v0.4.0-dev-debug.apk`（versionCode 5），SHA-256 `ED10F0E43F7D954E231A1718769CFEEE05D5785DBA32B9DCCC04D9FD2F488462`，55,903,025 字节，v2 签名校验通过。已通过 `adb install -r` 在手机 `23127PN0CC`（Android API 36）覆盖安装，已安装 APK 哈希与本机一致。此包尚未上传 GitHub；APK 与 `.tools/` 不进入 Git。

2026-09-21 音频处理续作：用户提供的 `source/` 有两段约 4/8.5 分钟 MP3 与五段约 1 小时雨声 MP3，没有海浪文件。当时未收到再分发授权声明，故未公开。已新增不覆盖原件的 `tools/prepare_loop.py`，本机生成五段约 298 秒的 Ogg 循环试听文件，最终候选及来源/输出哈希在忽略目录 `deliverables/audio-previews-v4/`。两段短 MP3 保持原样。七段已复制到手机 `Download/minimal-sleep-loop-previews-v4/` 并核对哈希；其中 `rain-01.ogg` 在现有 App 内导入和短时播放成功，测试导入副本已在 App 中删除。详见 [本地循环剪辑](audio-looping.md) 与 [验证记录](validation.md)。

2026-09-22 私有试听更新：用户允许裁剪后，将 `rain-01.ogg` 和 `rain-04.ogg` 放入 Git 忽略的 debug 专用资源目录，形成仅本机安装的 `deliverables/minimal-sleep-v0.3.1-local-rain-debug.apk`，59,743,130 字节，SHA-256 `0EA1DB88FCE7829C6F5DD66B500D4E555CADD71309186A65D89A456386760244`，仍为 versionCode 4。`lintDebug testDebugUnitTest assembleDebug` 和 `assembleRelease` 通过；release APK 不含这两段素材。手机覆盖安装成功，安装包 SHA 与本机一致；界面出现两项，媒体会话分别播放并推进位置，切换及暂停通过短测。`rain-01.ogg` 的媒体会话经过 298 秒边界后维持 `PLAYING` 且位置回到开头；`rain-04.ogg` 未做全长循环测试，两段的接缝听感与主观响度尚未验证。该私有 APK 含未核实再分发权利的外来录音，**不上传、不推送、不公开发布**；此前“未内置 APK”仅描述 2026-09-21 的状态。

2026-09-22 当前调整：用户确认两段拟内置音轨由本人录制，授权以 Resker666 署名按 CC BY 4.0 修改、随源码与 APK 分发；原始 MP3 文件名带视频编号，权属依据是用户本人的明确声明，并非依据文件名推断。两段 Ogg 已移入 `app/src/main/assets/local-sounds/`，仅这两段进入 Git；其他五段候选与全部原始 MP3 仍留在忽略目录。粉红/棕噪声的选择项和 APK WAV 已移除，白噪声及合成大雨/海浪保留。`lintDebug testDebugUnitTest assembleDebug assembleRelease` 及 10 个 Python 测试通过；debug/release APK 内容核对为两段 Ogg 加三段生成 WAV。真机页面顺序、默认大雨剪辑、两段剪辑与白噪声短时播放切换均通过；无主观听感结论。

下一步：用户在手机上试听当前 APK 的两段雨声，特别检查约 298 秒循环处、响度和雷声是否影响入睡。其余五段本地候选若以后拟内置，仍须逐段核实作者与授权。另需验证 15 分钟实际到期、耳机拔出、焦点、权限拒绝。M3 收集来源与许可明确、按录音来源拆分的鼾声/人声/咳嗽/背景声/静音样本，只在本机或获授权的公开样本上评估并记录误报/漏报；不得上传私人夜间录音。M4 做白噪声+人声/鼾声对照及趋势/协调器。M5 补保留、收藏、主动导出和异常恢复，再安排至少 8 小时受控整夜与不充电耗电试验。不能把既有短测或条件不明的长会话说成受控整夜验收通过。

2026-09-22 构建流水线：新增 `.github/workflows/android-apk.yml`，在 `main` 与 `codex/**` 推送时运行 Python 音频工具测试、Android Lint、JVM 单元测试并构建调试 APK，成功后上传 APK 和 SHA-256 文件为 14 天的 Actions 产物。开发分支首次成功运行见 [#5](https://github.com/Resker666/minimal-sleep/actions/runs/35673768789)；合入主干后的成功运行见 [#8](https://github.com/Resker666/minimal-sleep/actions/runs/35730491051)。工作流不发布 GitHub Release。

待做：设计并配置受保护的**固定签名密钥**，使将来的云端 APK 可以覆盖安装已用同一密钥签名的版本。先核对当前手机 APK 的签名证书、决定是否迁移，以及密钥备份和 GitHub Secrets 管理方案；本轮不设置任何签名密钥，也不声称云端调试 APK 能覆盖当前手机版本。卸载当前 App 会删除私有录音和导入音频，迁移前需设计用户主动导出或备份路径。

2026-09-23 iOS CI 第一阶段：新增 `.github/workflows/ios-build.yml`，在 `main`、`codex/**` 及相关 Pull Request 的 iOS 文件变更时使用 GitHub `macos-26` runner。工作流动态选择可用 iPhone 模拟器，运行 XCTest，随后以 `CODE_SIGNING_ALLOWED=NO` 构建 Release 模拟器 App，使用 `ditto` 打包并生成 SHA-256，成功后上传 14 天的 Actions 产物。首次开发分支云端运行 [#1](https://github.com/Resker666/minimal-sleep/actions/runs/35852288923) 已成功，生成 `minimal-sleep-ios-simulator-1`。工作流不包含 Apple ID、Personal Team、证书或 Team ID；产物只能在 iOS 模拟器中运行，不能安装到 iPhone。正式 IPA/TestFlight 和 Android 固定发布签名均留到第二阶段。

## 2026-09-24 iOS 生成音频与本机复验

- Git 历史清理已经完成，后续不再重写。Android 继续直接使用已跟踪的 `rain-01.ogg` 和 `rain-04.ogg`；iOS 从同一组 Ogg 生成被忽略的 44.1 kHz、双声道、16-bit PCM WAV。仓库当前版本和可达历史不再保存两个约 52 MB 的派生 WAV。
- `.gitignore` 保护两个最终 WAV 和转码临时文件；iOS CI 配置已加入生成、清单一致性与 App 包五资源检查。新的云端运行结果将在推送后另行记录。
- 本机 4 个音频准备测试、31 个 iOS XCTest、未签名 Release 模拟器构建及 App 包五个声音检查均通过。真机可靠性项目仍未执行。
