# minimal-sleep iOS：桌面端 Codex 执行文档

> 给执行代理：按任务顺序实施。若安装了 Superpowers，使用 `superpowers:executing-plans`；否则使用本机等效的计划、实现、验证流程。无需安装这些技能才能执行。勾选框用于记录真实进度。

**目标：** 在现有仓库新增原生 iOS 客户端，先交付用户自己愿意每天使用的离线助眠播放版，再逐步增加夜间录音与本地疑似声音分类。

**架构：** 保留 Android Kotlin/Compose 工程，在 `ios/` 新增 SwiftUI 工程。iOS 使用 AVFoundation 音频能力，共用产品规则、授权素材和模型定义；首版不引入跨平台重构。

**技术栈：** Swift、SwiftUI、AVFoundation、MediaPlayer、Foundation；首版不依赖服务器、账号系统、第三方分析 SDK。

**设计依据：** 本文第 1～4 节即随文设计规格。任务 0～5 是首轮执行范围，第 7 节是后续路线，不代表首轮要实现所有功能。

编写日期：2026-09-22。仓库：https://github.com/Resker666/minimal-sleep

## 1. 已确认的用户需求与环境

- 产品理念：极简、免费、开源、无广告，以自己喜欢使用为第一目标。
- 已有 Android 项目，希望新增 iOS 版，继续使用同一个仓库。
- 用户有今年购买的 M4 Mac 小主机，以及运行 iOS 27 的 iPhone。
- macOS、Xcode、iOS 27 的具体小版本和构建号尚未核实；执行时读取实际环境。不能只根据购买年份认定工具链兼容。
- 本文用于 Mac 上的桌面端 Codex 实施；本次文档编写没有运行 Xcode，也没有验证任何 iOS 功能。
- 默认自用开发，不要求首轮购买开发者会员或上架。

## 2. 仓库基线与必须先读的文件

2026-09-22 读取远程 main 的结果：Android 使用 Kotlin、Compose、Media3、AudioRecord、Room、LiteRT。已有两段授权雨声剪辑、白噪声、合成大雨和海浪；支持音频导入、定时淡出、事件片段和本地疑似分类。Android 受控整夜可靠性、分类准确率仍未验收。

执行时以本地实际分支和代码为准，先读取：

- 根目录及路径相关的 `AGENTS.md`（如有）。
- `README.md`、`docs/progress.md`、`docs/validation.md`。
- `docs/assets.md`、`docs/model-assets.md`、`assets-manifest.csv`、`THIRD_PARTY_NOTICES.md`、`LICENSE`。
- `app/build.gradle.kts`、实际音频素材、播放器和音频导入实现。

用 `rg --files` 定位具体文件，不猜测 Kotlin 类名或照搬本文快照。记录起始分支、提交 SHA、现有未提交修改。不得 reset、clean 或覆盖用户未提交工作。

## 3. 全局约束与首版设计

### 3.1 产品边界

首版包含：内置声音、循环播放、音量、15/30/60/90 分钟或整晚、最后 10 秒淡出、后台播放、锁屏控制、本地音频导入和删除、简短隐私/资源说明。

首版不包含：麦克风权限、录音、模型推理、睡眠评分、深浅睡判断、闹钟、HealthKit、Apple Watch 客户端、账号、同步、联网下载。

不把 Android 尚未验证的能力写成已经可靠，也不把声音记录描述成医学诊断。

### 3.2 工程决策

- 新建 `ios/MinimalSleep.xcodeproj`，共享 scheme 名称为 `MinimalSleep`；提交可直接由 Xcode 打开的工程。
- 默认 deployment target 为 iOS 17.0，作为首版工程决策；用户的 iOS 27 真机是当前实测目标，不宣称所有旧系统均已验收。
- 使用本机可兼容真机的正式 Xcode；若只有预览工具链可支持真机，明确记录，不自动升级系统。
- App 名称“极简睡眠”，建议 Bundle ID `io.github.resker666.minimalsleep`；若签名冲突，先说明具体原因再调整。不得虚构 Development Team。
- 首版使用 AVAudioPlayer 循环播放；用一个音频协调器统一管理 AVAudioSession、路由、中断、远程控制和状态。
- 播放模式使用 `.playback`；后台模式只启用真实需要的 audio。
- 用 MPNowPlayingInfoCenter / MPRemoteCommandCenter 提供锁屏标题、播放和暂停。循环素材不显示误导性的“整夜录音时长”。
- 倒计时使用可注入的单调时钟和截止时刻计算；不能把 UI Timer 的触发次数当作真实经过时间。
- “暂停”只暂停声音，助眠倒计时继续流逝；“停止”清除本次倒计时。改变时长从操作时重新计时。到期后即使再次收到播放命令，也不得意外恢复已结束会话。
- 定时最后 10 秒按基础音量乘以剩余时间比例淡出；期间调音量不绕过淡出。到期停止并清理锁屏状态。
- 其他 App 或来电中断时暂停，首版不自动恢复；耳机断开时暂停，防止突然外放。可恢复时向用户提供明确播放操作。
- 冷启动恢复偏好，不自动播放。播放失败显示可理解的错误，界面和锁屏状态保持一致。

### 3.3 音频与存储

- 优先使用仓库中已明确可再分发的素材，不加入本地私有候选录音。
- Android 雨声采用 Ogg；不要假定 iOS 播放器支持相同编码。核验容器与编码，必要时生成 iOS 兼容的 M4A/AAC 或 PCM WAV 派生资源，不覆盖 Android 原件。
- 转码后记录源文件/输出 SHA-256、命令、编码参数、作者及许可证，保留 CC BY 4.0 署名和修改说明。
- 循环接缝必须试听跨越实际素材边界；编译成功或播放进度归零不等于无缝。若 AVAudioPlayer 对所选编码有明显接缝，优先换兼容资源格式，再评估更复杂的播放器。
- 音频导入使用系统文件选择器，以可解码的 MP3/M4A/WAV 为首批验收格式；扩展名或 UTType 通过不代表内容可播放。
- 获取安全作用域访问后复制到 App 私有 Application Support 目录，使用内部 UUID 文件名，并在完成或失败时释放访问。
- 按现有规则限制：最多 10 个导入文件，单文件最多 100 MiB，总量最多 300 MiB；复制完成后设备可用空间仍应不少于 200 MiB。以字节校验，不只依赖文件名或提供方元信息。
- 临时复制、解码检查、原子落盘成功后才加入索引；失败清理临时文件。用户取消导入不提示为错误。
- 首版用 Codable JSON 保存导入索引，用 UserDefaults 保存非敏感偏好；无需为几个配置引入数据库依赖。
- 对导入音频目录设置备份排除属性并验证；iOS 没有 Android 式 INTERNET 权限开关，不用“无联网权限”描述 iOS。准确表述为“应用不主动上传数据，无分析 SDK”。
- 删除正在播放的导入音频时先停止，再删除文件与索引；更新和重启应保留其余导入数据。

### 3.4 界面

一个简洁主页面展示声音列表、当前音轨、播放/暂停、音量和关闭时间；导入与删除入口清晰。深色环境下不刺眼，适配动态字体和 VoiceOver 标签。资源/隐私说明可以用轻量 sheet，不增加无必要的导航层级。

## 4. 文件职责与重点失败场景

建议文件布局如下；如发现已有 iOS 工程，沿用其结构，不另建重复工程。

| 路径 | 职责 |
| --- | --- |
| `ios/MinimalSleep.xcodeproj` | 工程、共享 scheme、构建配置 |
| `ios/MinimalSleep/App/MinimalSleepApp.swift` | 应用入口、依赖装配 |
| `ios/MinimalSleep/Playback/AudioCoordinator.swift` | 唯一音频会话和播放状态管理 |
| `ios/MinimalSleep/Playback/SleepTimerPolicy.swift` | 截止时刻、淡出纯逻辑 |
| `ios/MinimalSleep/Playback/NowPlayingController.swift` | 系统锁屏信息和远程命令 |
| `ios/MinimalSleep/Library/SoundCatalog.swift` | 内置音轨定义 |
| `ios/MinimalSleep/Library/ImportedSoundStore.swift` | 导入、索引、容量、删除 |
| `ios/MinimalSleep/Views/HomeView.swift` | 助眠主页面 |
| `ios/MinimalSleep/Views/AboutView.swift` | 隐私与资源署名 |
| `ios/MinimalSleep/Resources/` | 已许可的 iOS 音频派生资源 |
| `ios/MinimalSleepTests/` | 时间规则、容量、索引一致性测试 |
| `docs/ios-development.md` | 环境、构建、签名与启动 |
| `docs/ios-validation.md` | 分层验证证据与待测项目 |
| `docs/ios-progress.md` | 本轮成果和下一步 |

优先验证五类失败，不只覆盖正常点击：

1. 锁屏期间倒计时到期：停止播放，不依赖界面刷新。
2. 来电或耳机断开：不意外外放或自动恢复。
3. 同名、损坏、大文件或空间不足：不覆盖旧音频，不留下索引垃圾。
4. 连续点击播放、切换、导入、删除：保持唯一播放器、无过期回调恢复声音。
5. 杀进程或安装更新：偏好和导入仍可读取，冷启动不自动发声。

## 5. 首轮实施任务：执行到可自用播放版

### 任务 0：核验环境和仓库

- [ ] 在用户选择的仓库工作；若未克隆，克隆公开仓库到用户指定项目目录。
- [ ] 读取第 2 节文件，记录差异；保护用户改动，以独立分支 `codex/ios-mvp` 开发，已有同名分支则先判断是否属于本任务。
- [ ] 执行以下只读命令，核对 Xcode 路径、SDK、模拟器和连接设备：

```bash
sw_vers
uname -m
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list devices available
xcrun devicectl list devices
git status --short
git branch --show-current
git rev-parse HEAD
```

- [ ] 将实际版本写入 `docs/ios-development.md`。若命令因只有 Command Line Tools 而失败，明确需要完整 Xcode；不把环境故障说成代码故障。
- [ ] 若需要用户打开 Xcode 接受协议、登录 Apple 账号、选择 Team、连接/信任 iPhone 或开启 Developer Mode，给出具体操作；仍继续完成不依赖该操作的代码、模拟器构建和文档。

完成标准：确定工具链是否可用、真实目标设备是否可见，记录具体阻塞，不凭年份判断。

### 任务 1：交付可构建的 SwiftUI 壳与可播放素材

- [ ] 建立第 4 节入口、主页面、声音目录和共享 scheme；优先无第三方运行时依赖。
- [ ] 核验并加入授权素材，必要时转码；先让白噪声和两段雨声可选择、播放、停止。合成大雨与海浪沿用现有资源，明确是合成音。
- [ ] 在 Xcode 工程配置资源、后台 audio、Bundle ID 和隐私说明入口；首版不得申请麦克风。
- [ ] 执行模拟器构建并修复失败：

```bash
xcodebuild -list -project ios/MinimalSleep.xcodeproj
xcodebuild -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/minimal-sleep-ios-derived build CODE_SIGNING_ALLOWED=NO
```

- [ ] 记录构建结果。`.gitignore` 排除 DerivedData、xcuserdata、证书、描述文件、私人音频；工程文件和共享 scheme 进入版本控制。

完成标准：工程可以从仓库构建，模拟器有可操作页面，素材许可完整。

### 任务 2：完成播放器、定时和后台行为

- [ ] 实现唯一 AudioCoordinator；所有 UI 和锁屏命令通过同一入口修改状态，避免并发创建播放器。
- [ ] 为 SleepTimerPolicy 编写有意义的测试：整晚无截止；15 分钟到期；剩余 10/5/0 秒淡出比例为 1/0.5/0；模拟长时间无 UI tick 后仍得到正确剩余时间；暂停不延长截止。
- [ ] 实现第 3.2 节定时规则、基础音量、切换音轨和过期回调失效机制。计时测试通过可注入时钟推进，不真的等 15 分钟。
- [ ] 加入后台音频配置、锁屏信息和播放/暂停命令；重复进入页面不重复注册远程命令。
- [ ] 处理 interruption、route change 和播放错误；按文档规定暂停，禁止未经用户操作恢复外放。
- [ ] 测试切换音轨后旧淡出回调失效、停止后远程播放不会恢复过期会话；在模拟器检查 UI 状态，后台音频行为留给真机实测。

完成标准：时间规则自动化通过；正常流程可演示；不声称模拟器证明整夜后台可靠。

### 任务 3：完成本地音频导入与持久化

- [ ] 实现 ImportedSoundStore，以第 3.3 节限额为统一常量；串行提交导入操作，防止并发突破数量或总容量。
- [ ] 测试数量 10/11 边界、100 MiB 边界、总量 300 MiB 边界、复制后剩余 200 MiB 边界；模拟磁盘空间和文件大小，无需生成几百 MiB 测试文件。
- [ ] 实现文件选择、作用域访问、临时复制、实际解码检查、原子提交及错误清理。
- [ ] 测试同名文件互不覆盖，失败不增加索引，删除当前曲目先停止，重启可读索引，损坏索引有可恢复的错误提示。
- [ ] 完成删除入口、持久偏好、备份排除和资源说明；不在日志输出音频内容或用户文件完整路径。

完成标准：支持实际 MP3/M4A/WAV 导入播放，失败可解释，磁盘与索引保持一致。

### 任务 4：构建、真机交接与验收

- [ ] 列出可用测试 destination，选择实际可用的 iPhone 模拟器运行测试；不要把示例 UDID 当作真实设备。记录实际完整命令与退出码。
- [ ] 执行 Debug 模拟器 build/test；执行通用 iOS 设备无签名构建，验证设备架构编译：

```bash
xcodebuild -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/minimal-sleep-ios-device-derived build CODE_SIGNING_ALLOWED=NO
```

- [ ] 明确无签名构建不能直接安装到 iPhone。由用户在 Xcode 登录 Apple 账号，选择 Personal Team 或已有付费 Team，再选择真机 Run；不得索取账号密码或将凭据写进文件。
- [ ] 用户连接且签名可用时协助安装，不卸载已有有数据的版本来“解决”更新问题。
- [ ] 按第 6 节记录真机结果。用户尚未操作的项目标记“待用户验证”，继续完成其余工作。

完成标准：给出可编译工程及准确安装步骤；已测、未测和阻塞分开记录。

### 任务 5：整理可接续交付

- [ ] 更新三个 iOS 文档和根 README 的平台状态；不覆盖 Android 既有进度。
- [ ] 整理 diff，确认未引入私有录音、密钥、构建缓存和无关 Android 修改。
- [ ] 有 Android 工具链时，对受到共同资源或脚本修改影响的部分做针对性回归；未改 Android 且无工具链时无需安装整套 Android SDK，只明确未运行 Android 测试。
- [ ] 向用户交付：变更摘要、工程路径、实际构建与测试结果、真机待测表、已知问题、下一步入口。
- [ ] 本次指令不要求自动推送、合并或发布。按用户已有 Git 工作习惯处理本地提交；若没有明确约定，保留可审阅改动并提供建议提交命令。

首轮结束位置：任务 0～5 完成可自动执行的部分；不要顺手加入录音、分类或上架流程。

## 6. 真机验收表

在 `docs/ios-validation.md` 每行记录设备/OS/Xcode、构建提交、测试条件、实际结果、证据和状态。没有执行的项目保持未测。

| 测试 | 预期 | 执行方式 |
| --- | --- | --- |
| 启动、切换、暂停、音量 | 页面与声音一致，无重复播放器 | 真机短测 |
| 雨声跨完整循环边界至少 2 次 | 无明显静音间隙、爆音或刺耳变化 | 用户耳听并记录曲目 |
| 锁屏播放 30～60 分钟 | 持续播放，锁屏按钮状态一致 | 真机，不依赖调试器保活 |
| 实际 15 分钟倒计时 | 最后 10 秒淡出，到期停止 | 真机锁屏测试 |
| 耳机断开、来电、其他 App 抢占 | 暂停且不意外外放/恢复 | 真机人工操作 |
| 本地及文件提供方导入 | 成功后离线可播放，取消无残留 | 用户选择合法测试素材 |
| 删除当前曲目、快速连续切换 | 无崩溃、无失效回调恢复旧曲目 | 真机短测 |
| 强制退出后重新打开、覆盖安装 | 不自动发声，偏好和导入可恢复 | 有数据时不得卸载 |
| 飞行模式使用 | 内置和已导入音频可用 | 真机测试 |
| 整晚播放 8 小时 | 无意外停止，记录耗电和温度感受 | 用户独立夜间测试 |

耗电测试记录起止电量、是否充电、低电量模式、屏幕状态、输出设备和时长。连接 USB 充电的结果不能作为续航数据。模拟器通过不替代锁屏和整夜真机验收。

## 7. 后续阶段：首轮完成后按需要推进

### 第二阶段：夜间声音记录

目标：保留可回听事件片段，保证记录连续性和真实中断信息。进入条件：助眠播放版可自用，用户要求继续录音阶段。

- 麦克风权限仅在用户开始记录时申请，添加准确用途说明和显著记录状态。
- 用一个 AVAudioEngine 输入链路读取实际采样格式，再重采样为 16 kHz 单声道；播放+录音使用适当的 playAndRecord 会话配置，不假定硬件采样率。
- 先实现仅录音验证，再联合播放；音频回调只做有界轻量处理，不执行磁盘阻塞操作或模型推理。
- 移植实际 Android 触发规则、约 3 秒前后缓冲和单片段 60 秒上限；阈值必须重新评估，不直接声称两平台效果相同。
- 保存会话、片段、播放区间、中断缺口、停止原因；文件写入与元数据提交要支持异常恢复。
- 初始录音总量上限 1 GiB，剩余空间低于 200 MiB 停止并记录原因；补足保留期、导出与收藏策略后再做对外发布。
- 录音采用适合锁屏后持续写入的数据保护配置，并排除备份；不能因默认文件保护导致锁屏后新建片段失败。真机验证整个夜间文件生命周期。
- 进程被结束后下一次启动，将未完成会话标记为中断，不伪造连续记录或自动悄悄重启录音。
- 首先完成 30～60 分钟锁屏测试，再完成 8 小时受控整夜；分别验证仅播放、仅录音、同时运行。

### 第三阶段：本地疑似声音分类

目标：在原音可靠保存后提供实验性标签。进入条件：录音链路通过真机验收。

- 复用仓库真实模型与标签 SHA-256，核对当时官方 LiteRT iOS 集成方式和依赖许可；不要照抄 Android Maven 依赖。
- 第一实现可在用户结束夜间记录、App 前台时分类；长批次持久化进度，支持下次继续，不能假定后台有无限推理时间。
- 验证单声道、16 kHz、15,600 样本窗口、归一化、补零等预处理与 Android 实际实现一致。
- 使用同一批来源合法的固定样本对照两端分数；误差容忍值由实际运行和算子差异确定，并记录。
- 标签使用“疑似鼾声”“人声/疑似梦话”“咳嗽”“其他环境声音”“未确定”；分数不是校准后的概率。
- 保存原始模型输出、模型版本和手动标签；播放重叠保持干扰标记，不把背景声误判包装成梦话识别成功。
- 模型失败仍可回听，未触发片段不等于没有声音；私人夜间录音不提交仓库、不自动上传。

### 第四阶段：对外测试与发布

仅当用户明确要分发时推进：核对当时开发者会员、TestFlight、SDK 和审核要求，准备隐私政策、录音说明、素材署名、签名与更新流程。免费自用账号的描述文件通常需定期重新签名，不能把开发包当作永久安装方式。

闹钟、HealthKit、趋势和 Apple Watch 属于独立后续需求，不为它们扩大首版。若加入闹钟，再核实 AlarmKit 的系统版本与授权要求。

## 8. 阻塞处理与状态汇报

执行可以跨多次会话，每次更新 `docs/ios-progress.md`：

```text
当前任务：
起始提交 / 当前分支：
本轮已完成：
构建与测试（实际命令、退出码）：
真机已验证：
真机未验证：
具体阻塞和用户最小操作：
下次从哪个文件/步骤继续：
```

环境或签名阻塞时，完成仍可完成的实现和静态/模拟器验证。不得为“通过测试”移除关键功能、放宽容量限制或将失败写成通过。不要自动付费、升级系统、擦除手机、上传私人录音或发布 App。

## 9. 官方参考资料

资料会更新，执行时优先查对应安装 SDK 的官方文档；不锁定本文未核实的 Xcode 或 Swift 最新版本。

- Xcode 系统要求：https://developer.apple.com/xcode/system-requirements
- Apple 开发者账号：https://developer.apple.com/help/account/basics/about-your-developer-account
- AVAudioSession：https://developer.apple.com/documentation/avfaudio/avaudiosession
- Play and record：https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord
- App 审核指南：https://developer.apple.com/app-store/review/guidelines/
- LiteRT iOS：https://ai.google.dev/edge/litert/ios/quickstart
- AlarmKit：https://developer.apple.com/documentation/alarmkit

## 10. 直接发给桌面端 Codex 的启动指令

> 请读取本文件，在 minimal-sleep 仓库中执行任务 0～5，完成第一版原生 iOS 离线助眠播放器。我的设备是 M4 Mac 和 iOS 27 iPhone，具体工具链请实际核验。先读项目现状与 AGENTS.md，保护现有 Android 工程和未提交修改，用 SwiftUI + AVFoundation 在 ios/ 新增实现。请持续完成代码、可执行测试、构建和交接文档，不只输出方案。遇到签名、Apple 账号、连接手机等必须我操作的步骤，告诉我具体操作，同时继续其他不受阻的工作。首轮不实现录音和分类，不自动推送或发布。最后给出真实测试结果和仍需我在 iPhone 上验证的清单。
