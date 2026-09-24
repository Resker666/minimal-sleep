# iOS 夜间声音片段录音设计

日期：2026-09-24
状态：已完成会话内设计确认，等待仓库文档审核
目标分支：`codex/ios-night-recording`

## 目标

为 iOS 客户端增加第一阶段夜间录音能力。用户主动开始记录后，App 在前台或锁屏状态持续监听麦克风，只把能量检测触发的短声音片段保存到 App 私有目录。助眠声可以同时播放；与播放重叠的片段必须标记为可能受播放影响，不能声称做了回声消除。

本阶段同时把 iOS 产品版本升级为 `0.5.0`、构建号升级为 `2`，并在关于页面显示“开发预览”。Android 版本保持 `0.4.0-dev`、`versionCode 5`。

## 用户需求和成功标准

用户已经确认以下行为：

- 使用声音触发片段方案，不保存整夜连续录音；
- 录音时允许继续播放内置或导入的助眠声音；
- 锁屏后继续录音；
- 支持夜间记录列表、片段回听、单条删除和整次记录删除；
- 第一阶段不加入 YAMNet 或其他声音分类模型；
- 录音只保存在本机，默认使用 1 GiB 总上限和 200 MiB 最低剩余空间保护；
- 只升级 iOS 版本号。

完成后，用户应能在真机上开始记录、锁屏、产生声音触发片段、停止记录、进入记录页回听和删除片段。模拟器自动化测试只能验证纯逻辑、文件格式和状态转换，不能替代真机麦克风、锁屏、音频路由和听感验证。

## 本阶段范围

### 包含

- 麦克风权限及中文用途说明；
- 16 kHz、单声道、16-bit PCM 采集；
- 自适应能量检测；
- 约 3 秒触发前缓冲、约 3 秒触发后缓冲；
- 每个 WAV 片段最长 60 秒；
- 夜间记录和片段元数据的原子 JSON 存储；
- 助眠声播放区间及播放干扰标记；
- 锁屏后台采集；
- 音频中断和不安全路由变化时安全停止，不自动恢复；
- 记录列表、片段回听、片段删除和整次记录删除；
- 录音空间保护和备份排除；
- iOS 版本 `0.5.0 (2)` 与关于页面更新；
- 单元测试、模拟器构建和真机分阶段验证。

### 不包含

- YAMNet、Core ML 或任何鼾声、梦话、咳嗽分类；
- 睡眠评分、深睡判断或呼吸暂停结论；
- 整夜连续原音保存；
- 回声消除；
- 云上传、账号或跨设备同步；
- 自动保留期、收藏保护或录音导出；
- 7 天或 30 天趋势；
- Android 功能或版本改动。

## 方案选择

采用 `AVAudioEngine` 实时采集、纯 Swift 能量检测与切片、WAV 文件加原子 JSON 索引的方案。

不使用 SwiftData 或 Core Data。当前数据规模有限，仓库已经在导入音频功能中使用 Codable 和原子文件替换；沿用同类存储边界能够减少依赖和迁移风险。未来需要跨夜查询和趋势时，再以明确的数据迁移设计切换到数据库。

不采用“先录整夜再切片”。该方案会短暂保存完整夜间原音，增加存储、隐私和异常恢复风险，与“只保存触发片段”的目标不一致。

## 总体架构

新增以下单元：

```text
App / SwiftUI
  ├─ AudioCoordinator                 现有助眠声播放状态
  ├─ NightRecordingCoordinator        夜间记录状态与用户操作入口
  ├─ AudioSessionController           播放和录音共享的音频会话仲裁
  ├─ MicrophoneCaptureEngine          AVAudioEngine 输入与格式转换
  ├─ EnergyDetector                   纯 Swift 能量触发逻辑
  ├─ EventSegmenter                   前后缓冲、分组与 60 秒切片
  ├─ RecordingStore                   私有目录、JSON、删除与空间策略
  ├─ WAVWriter                        原子写入 16-bit PCM WAV
  ├─ TonightView                      播放与夜间记录入口
  └─ RecordingHistoryView             夜间列表、片段详情与回听
```

每个单元只承担一个职责：采集引擎不写磁盘，切片器不知道 SwiftUI，存储层不管理麦克风，界面不直接操作 AVAudioEngine。

## 音频会话协调

当前 `AVAudioPlayerPlaybackEngine` 会在播放时设置 `.playback`，暂停或停止时直接停用共享 `AVAudioSession`。录音加入后，这种行为会导致暂停助眠声时同时关闭麦克风。

新增 `AudioSessionController`，集中维护两个用途状态：

- `playbackActive`
- `recordingActive`

会话规则：

| 播放 | 录音 | 会话配置 |
|---|---|---|
| 否 | 否 | 停用会话并通知其他 App |
| 是 | 否 | `.playback` + `.default` |
| 否 | 是 | `.playAndRecord` + `.default` + `.defaultToSpeaker` |
| 是 | 是 | `.playAndRecord` + `.default` + `.defaultToSpeaker` |

`AVAudioPlayerPlaybackEngine` 和 `NightRecordingCoordinator` 只更新各自用途状态，不再直接决定是否停用整个共享会话。录音结束但播放仍在继续时，会话切回 `.playback`；两者都停止后才停用。

中断通知和路由变化通知也由该控制器统一分发：

- 系统音频中断开始：暂停助眠声并结束夜间记录；
- 旧输出设备不可用，例如耳机断开：暂停助眠声并结束夜间记录，防止声音突然从扬声器播放；
- 不自动恢复播放或录音；
- 界面显示明确的中断原因，用户必须主动重新开始。

第一阶段不承诺蓝牙麦克风或特定外接设备兼容性。真机验证记录实际输入和输出路由。

## 麦克风采集

`MicrophoneCaptureEngine` 使用 `AVAudioEngine.inputNode` 安装输入 tap。输入 tap 只复制必要的音频缓冲，不在实时音频线程写文件或更新 JSON。

采集数据通过串行处理队列交给 `AVAudioConverter`，统一转换为：

- 采样率：16,000 Hz；
- 声道：单声道；
- 格式：signed 16-bit little-endian PCM；
- 逻辑处理帧：每帧 1,024 个样本。

转换后的 PCM 帧依次传给 `EnergyDetector` 和 `EventSegmenter`。开始采集前验证输入格式和转换器；任一步失败都不创建伪造的完整记录。

## 能量检测和切片

第一阶段沿用 Android 已有参数，使两个平台行为可比较：

- 初始背景 RMS：`0.004`；
- 候选阈值：`max(0.012, backgroundRms × 2.5)`；
- 触发时缓慢更新背景，安静时较快适应；
- 连续强声超过当前保护窗口时逐渐适应，避免永久保持触发状态。

这些阈值未经真实鼾声或人声样本校准，只表示“声音能量候选”，界面统一称为“声音片段”。没有片段不能解释为整晚安静。

`EventSegmenter` 使用固定参数：

- 触发前 3 秒环形缓冲；
- 最后一次候选后继续保留 3 秒；
- 单文件最多 60 秒；
- 同一持续事件超过 60 秒时拆为多个文件，但保留同一 `groupID`；
- 用户停止或发生中断时，把当前非空片段安全收尾。

16 kHz 单声道 16-bit PCM 的 60 秒文件约为 1.92 MB，不包含 WAV 头部的少量开销。

## 播放干扰记录

`NightRecordingCoordinator` 读取 `AudioCoordinator` 发布的只读播放快照：

- 是否正在播放；
- 当前声音 ID；
- 应用音量；
- 状态变化对应的录音样本位置。

录音期间每次播放开始、暂停、停止、切换声音或改变音量时，关闭旧区间并开启新区间。区间使用录音会话内的样本位置，而不是墙钟时间，避免系统时间变化造成错位。

保存片段时，只要片段样本范围与任意播放区间重叠，就设置 `playbackAffected = true`。记录页显示“播放声音期间，片段可能受影响”。该字段是干扰说明，不代表已经消除播放声，也不代表片段不能回听。

## 数据模型

### RecordingSession

```text
id: UUID
startedAt: Date
endedAt: Date?
timeZoneIdentifier: String
capturedSamples: Int64
status: recording | completed | interrupted
endReason: String?
eventCount: Int
```

### RecordingEvent

```text
id: UUID
sessionID: UUID
groupID: UUID
startSample: Int64
sampleCount: Int64
fileName: String
playbackAffected: Bool
createdAt: Date
```

### RecordingPlaybackInterval

```text
id: UUID
sessionID: UUID
soundID: String
appVolume: Float
startSample: Int64
endSample: Int64
```

所有模型使用带显式 `schemaVersion` 的 Codable JSON。第一版 schema 为 `1`。未知的新版本必须返回可理解的“不支持的数据版本”错误，不能静默覆盖。

## 本地文件布局

```text
Application Support/
  NightRecordings/
    index.json
    Sessions/
      <session-id>/
        session.json
        <event-id>.wav
```

`index.json` 只保存列表所需摘要。`session.json` 保存完整会话、片段和播放区间。

写入规则：

1. WAV 先写 `<event-id>.wav.part`；
2. 写入完整 RIFF/WAVE 头和 PCM 后同步并原子改名；
3. 只有 WAV 成功发布后才把事件加入 `session.json`；
4. JSON 先写临时文件，再使用原子替换；
5. `session.json` 成功后更新 `index.json`；
6. 任一步失败都清理对应临时文件，不删除已完成片段。

`RecordingStore` 使用 actor 或等价串行边界，确保开始、追加片段、结束和删除不会并发修改同一索引。

启动恢复规则：

- 扫描 `Sessions` 重建缺失或损坏的 `index.json`；
- 状态仍为 `recording` 的旧会话改为 `interrupted`，原因写为“App 意外退出”；
- 无法解析的会话目录保持原样，不自动删除，并向界面报告读取失败；
- `.part` 临时文件可清理，但正式 WAV 不做推测性删除。

整个 `NightRecordings` 目录设置为排除系统备份。

## 空间策略

开始记录前、每分钟以及保存片段前检查：

- `NightRecordings` 总文件大小不得达到 1 GiB；
- 设备可用空间不得低于 200 MiB。

达到限制后：

1. 完成当前已经触发且能安全落盘的片段；
2. 结束会话并标记 `interrupted`；
3. 写入实际原因；
4. 在界面显示错误；
5. 不自动删除旧录音。

第一阶段只支持用户手动删除。自动保留期和收藏保护留到后续阶段。

## SwiftUI 页面

根页面改为 `TabView`：

- “今晚”：现有声音、播放、音量、定时和导入功能；
- “记录”：夜间记录列表与片段详情。

### 今晚页

新增“夜间记录”区域：

- 开始夜间记录；
- 结束夜间记录；
- 状态：准备中、记录中、正在保存、已停止、异常中断；
- 有效采集时长；
- 已保存片段数量；
- “录音只保存在本机”；
- “播放声音可能被麦克风录入”。

首次点击开始时请求麦克风权限。权限被拒绝时显示原因和前往系统设置的说明，但播放功能继续可用。

### 记录页

列表项显示开始时间、有效采集时长、片段数量和完成状态。详情页显示每段的会话内时间、长度、播放干扰标记，以及回听和删除按钮。

录音进行期间禁用回听、片段删除和整次记录删除。回听片段前暂停当前助眠声，不自动恢复，确保用户能听清片段。删除正在回听的片段前先停止回听。

记录页不显示鼾声、梦话、咳嗽或其他推断标签，统一显示“声音片段”。

## 权限、后台和隐私

`Info.plist` 新增：

```text
NSMicrophoneUsageDescription = 极简睡眠只在你主动开始夜间记录后使用麦克风，并仅在本机保存声音触发片段。
```

项目已经声明 `UIBackgroundModes = audio`。录音运行时保持活动的 `.playAndRecord` 会话和 `AVAudioEngine`，用于锁屏采集。后台能力只能通过真机验证，不能从配置或模拟器测试推断通过。

隐私约束：

- 不新增网络权限、分析 SDK 或上传路径；
- 不把任何真机录音复制到仓库；
- 自动化测试使用程序生成的短 PCM 数据；
- 关于页面明确只保存触发片段、播放可能造成干扰、普通删除不等于闪存安全擦除；
- 关于页面删除“不申请麦克风权限”和“无损 PCM 派生资源”等过期描述。

## 错误处理

错误分为用户可处理和会话终止两类。

用户可处理：

- 权限未决定：发起系统请求；
- 权限拒绝：不启动录音，显示设置说明；
- 暂无记录：显示空状态；
- 单个历史文件缺失：该项显示不可回听，但其他记录仍可用。

需要结束会话：

- 麦克风初始化或格式转换失败；
- 音频中断；
- 不安全路由变化；
- 输入读取停止；
- WAV 或 JSON 持久化失败；
- 空间低于限制；
- App 生命周期无法继续安全采集。

结束流程必须尽力完成当前片段、关闭播放区间、更新会话状态、停止 AVAudioEngine，并让音频会话恢复到与播放状态一致的配置。任何中断都不自动重新开启麦克风。

## 版本和关于页面

只修改 iOS：

- `MARKETING_VERSION = 0.5.0`；
- `CURRENT_PROJECT_VERSION = 2`；
- Debug 和 Release 保持一致；
- 关于页面从 Bundle 读取并显示 `版本 0.5.0 (2) · 开发预览`。

Android 的 `versionName = "0.4.0-dev"` 和 `versionCode = 5` 不变。

版本升级保持 Bundle ID 不变，真机使用同一签名覆盖安装时应保留导入音频和其他 App 私有数据。不能通过卸载方式进行升级验证。

## 测试策略

### 纯逻辑测试

- 能量阈值、背景噪声适应和持续强声保护；
- 3 秒前缓冲和 3 秒后缓冲；
- 60 秒边界拆分及同组 `groupID`；
- 停止时完成非空片段；
- 播放区间与片段的交集判断；
- 会话状态转换和不自动恢复规则；
- 1 GiB 与 200 MiB 边界。

### 存储测试

- WAV 头、采样率、声道、位深和样本数；
- 临时文件成功后原子发布；
- WAV 失败时不写入事件；
- JSON 往返、schemaVersion 和原子替换；
- 损坏索引从会话目录重建；
- 旧 `recording` 会话恢复为 `interrupted`；
- 删除片段和整次记录；
- 目录备份排除。

### 协调器测试

使用协议和 fake，不依赖真实麦克风：

- 权限允许、拒绝和受限；
- 开始、停止、重复点击和错误状态；
- 同时播放与录音的音频会话配置；
- 暂停播放时录音会话仍保持；
- 录音结束后播放继续时切回 `.playback`；
- 中断和耳机断开同时停止录音并暂停播放；
- 历史回听会暂停助眠声且不自动恢复。

### 构建与 CI

- 完整 XCTest；
- Release 模拟器无签名构建；
- App 包仍包含五段内置声音；
- `Info.plist` 包含麦克风说明和后台 audio；
- 构建设置解析为 iOS `0.5.0 (2)`；
- Android 测试继续通过，且 Android 版本文件无变化。

### 真机验证

按以下顺序记录实际证据：

1. 首次权限允许和拒绝路径；
2. 仅录音短测，制造安静、拍手和说话样本；
3. 同时播放与录音，确认重叠片段被标记；
4. 锁屏至少 30 分钟，确认有效采集时长连续；
5. 来电或系统中断、耳机断开和路由变化；
6. 停止后回听、删除片段和删除整次记录；
7. 覆盖安装，不卸载，确认已有导入音频和录音保留；
8. 短测稳定后再安排 8 小时受控整夜验证。

真机测试不得复制、上传或提交用户的实际录音。只记录时长、文件大小、状态、界面结果和用户听感。

## 预计文件变化

```text
ios/MinimalSleep/App/MinimalSleepApp.swift
ios/MinimalSleep/Info.plist
ios/MinimalSleep/Playback/AudioCoordinator.swift
ios/MinimalSleep/Playback/AVAudioPlayerPlaybackEngine.swift
ios/MinimalSleep/Playback/AudioSessionController.swift
ios/MinimalSleep/Recording/RecordingModels.swift
ios/MinimalSleep/Recording/EnergyDetector.swift
ios/MinimalSleep/Recording/EventSegmenter.swift
ios/MinimalSleep/Recording/WAVWriter.swift
ios/MinimalSleep/Recording/RecordingStore.swift
ios/MinimalSleep/Recording/MicrophoneCaptureEngine.swift
ios/MinimalSleep/Recording/NightRecordingCoordinator.swift
ios/MinimalSleep/Views/RootTabView.swift
ios/MinimalSleep/Views/HomeView.swift
ios/MinimalSleep/Views/RecordingHistoryView.swift
ios/MinimalSleep/Views/AboutView.swift
ios/MinimalSleepTests/*Recording*Tests.swift
ios/MinimalSleep.xcodeproj/project.pbxproj
docs/ios-development.md
docs/ios-progress.md
docs/ios-validation.md
README.md
```

如果实现时可以复用现有文件或自动同步目录，不为了匹配此列表强行创建空壳文件。

## 完成标准

1. iOS 版本为 `0.5.0 (2)`，关于页面显示版本和开发预览；
2. 用户主动授权后可以开始和结束夜间记录；
3. 锁屏时录音设计可运行，并取得至少一次真机验证证据；
4. 只保存触发片段，不保存整夜连续原音；
5. 片段为 16 kHz、单声道、16-bit PCM WAV，并符合前后缓冲和 60 秒上限；
6. 同时播放可用，重叠片段准确标记播放干扰；
7. 中断和不安全路由变化不会自动恢复麦克风；
8. 记录列表、回听、片段删除和整次记录删除可用；
9. 录音目录被排除备份，空间限制有自动化边界测试；
10. 完整 XCTest、模拟器构建和现有 Android CI 通过；
11. 文档明确未加入声音分类、未做回声消除、没有整夜可靠性结论；
12. Personal Team、证书、描述文件、生成 M4A 和真机录音不进入 Git。
