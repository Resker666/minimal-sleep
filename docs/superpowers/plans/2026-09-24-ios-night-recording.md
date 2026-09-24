# iOS 夜间声音片段录音 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 iOS 0.5.0 开发预览增加用户主动开启、锁屏持续、只保存声音触发 WAV 片段的本地夜间录音，并支持播放干扰标记、记录回听和删除。

**Architecture:** 使用统一 `AudioSessionController` 仲裁现有助眠声播放与新的 `.playAndRecord` 麦克风会话；`MicrophoneCaptureEngine` 输出 16 kHz 单声道 PCM 流，由串行 `RecordingPipeline` 完成能量检测、前后缓冲、播放区间观察和切片。`RecordingStore` 以 actor 串行保存原子 WAV、`session.json` 和 `index.json`，SwiftUI 通过 `NightRecordingCoordinator` 与 `RecordingLibrary` 展示“今晚/记录”两个标签。

**Tech Stack:** Swift 5、SwiftUI、Combine、AVFoundation、Foundation Codable/actor、XCTest、Xcode 27、iOS 17+、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-09-24-ios-night-recording-design.md`

## Global Constraints

- 只修改 iOS；Android 保持 `versionName = "0.4.0-dev"`、`versionCode = 5`。
- iOS 最低版本保持 17.0，产品版本改为 `0.5.0`、构建号改为 `2`。
- 录音只在用户主动开始后运行，只保存声音触发片段，不保存整夜连续原音。
- PCM 固定为 16,000 Hz、单声道、signed 16-bit little-endian；前缓冲 3 秒、后缓冲 3 秒、单文件最多 60 秒。
- 允许助眠声与录音同时运行；重叠只做 `playbackAffected` 标记，不声称回声消除。
- 音频中断和不安全路由变化必须停止录音且不自动恢复。
- 录音目录最多 1 GiB；可用空间低于 200 MiB 时安全停止，不自动删除旧录音。
- 第一阶段不加入声音分类、趋势、云上传、导出、自动保留期或收藏。
- Personal Team、证书、描述文件、生成 M4A 和真机录音不得进入 Git。
- 新文件由 Xcode 27 的 `PBXFileSystemSynchronizedRootGroup` 自动纳入 target；不要添加手工 PBX 文件引用。
- 只记录实际执行过的测试；模拟器结果不得写成真机麦克风或后台通过。

## Review Focus

1. **暂停助眠声时录音仍在运行：** `AudioSessionControllerTests` 必须验证 playback 从 true 变为 false 时，只要 recording 为 true，会话仍是 active `.playAndRecord`。
2. **60 秒持续强声不会覆盖或丢失样本：** `EventSegmenterTests` 必须验证连续候选拆成多个文件、样本总数一致且 `groupID` 相同。
3. **WAV 成功但 JSON 失败不会产生可见幽灵事件：** `RecordingStoreTests` 必须分别注入 session 与 index 保存失败。session 保存失败时回滚正式 WAV；index 保存失败时保留已经可恢复的 session/WAV，并在下次恢复时从 session 重建 index。
4. **App 崩溃后旧 recording 会话不能继续显示为正在录音：** 恢复测试必须把旧状态改成 interrupted，并保留正式 WAV。
5. **音频中断和耳机断开不能偷偷恢复麦克风：** `NightRecordingCoordinatorTests` 必须验证 capture 停止、session 结束且后续系统恢复通知不会调用 start。

---

## 文件结构

### 新增产品文件

- `ios/MinimalSleep/Playback/AudioSessionController.swift`：共享音频会话状态机、系统通知和安全事件。
- `ios/MinimalSleep/Recording/RecordingModels.swift`：Codable 会话、片段、播放区间、摘要和错误类型。
- `ios/MinimalSleep/Recording/EnergyDetector.swift`：无 I/O 的 RMS 候选检测。
- `ios/MinimalSleep/Recording/EventSegmenter.swift`：环形前缓冲、后缓冲、60 秒切片。
- `ios/MinimalSleep/Recording/PCM16WAVWriter.swift`：原子 WAV 编码接口和文件实现。
- `ios/MinimalSleep/Recording/RecordingStore.swift`：actor、JSON 索引、恢复、空间和删除事务。
- `ios/MinimalSleep/Recording/MicrophoneCaptureEngine.swift`：AVAudioEngine、AVAudioConverter 和 `AsyncThrowingStream<[Int16], Error>`。
- `ios/MinimalSleep/Recording/RecordingPipeline.swift`：按顺序消费 PCM、检测、切片、观察播放并调用存储。
- `ios/MinimalSleep/Recording/NightRecordingCoordinator.swift`：权限、开始/停止、安全事件和 UI 状态。
- `ios/MinimalSleep/Recording/RecordingLibrary.swift`：历史数据加载、回听和删除的主线程适配层。
- `ios/MinimalSleep/Views/RootTabView.swift`：今晚与记录两个标签。
- `ios/MinimalSleep/Views/RecordingControlsView.swift`：开始/停止、状态、时长和隐私提示。
- `ios/MinimalSleep/Views/RecordingHistoryView.swift`：会话列表、详情、回听和删除。

### 修改产品文件

- `ios/MinimalSleep/Playback/AudioCoordinator.swift`：发布只读播放快照，使用共享安全事件。
- `ios/MinimalSleep/Playback/AVAudioPlayerPlaybackEngine.swift`：通过 `AudioSessionController` 声明播放用途，不直接停用共享会话。
- `ios/MinimalSleep/App/MinimalSleepApp.swift`：组装共享依赖和根 TabView。
- `ios/MinimalSleep/Views/HomeView.swift`：嵌入夜间记录控制区。
- `ios/MinimalSleep/Views/AboutView.swift`：隐私、资源格式和动态版本文案。
- `ios/MinimalSleep/Info.plist`：麦克风用途说明。
- `ios/MinimalSleep.xcodeproj/project.pbxproj`：只改两套 iOS target 版本设置。
- `.github/workflows/ios-build.yml`：检查版本、权限说明和后台 audio。

### 新增测试文件

- `ios/MinimalSleepTests/EnergyDetectorTests.swift`
- `ios/MinimalSleepTests/EventSegmenterTests.swift`
- `ios/MinimalSleepTests/RecordingModelsTests.swift`
- `ios/MinimalSleepTests/PCM16WAVWriterTests.swift`
- `ios/MinimalSleepTests/RecordingStoreTests.swift`
- `ios/MinimalSleepTests/AudioSessionControllerTests.swift`
- `ios/MinimalSleepTests/RecordingPipelineTests.swift`
- `ios/MinimalSleepTests/NightRecordingCoordinatorTests.swift`
- `ios/MinimalSleepTests/RecordingLibraryTests.swift`
- `ios/MinimalSleepTests/AppVersionTests.swift`

### 文档

- `README.md`
- `docs/ios-development.md`
- `docs/ios-progress.md`
- `docs/ios-validation.md`

---

### Task 1：能量检测与事件切片

**Files:**
- Create: `ios/MinimalSleep/Recording/EnergyDetector.swift`
- Create: `ios/MinimalSleep/Recording/EventSegmenter.swift`
- Create: `ios/MinimalSleepTests/EnergyDetectorTests.swift`
- Create: `ios/MinimalSleepTests/EventSegmenterTests.swift`

**Interfaces:**
- Produces: `EnergyDetector.isCandidate(_ samples: [Int16]) -> Bool`
- Produces: `RecordingAudioSegment(groupID:startSample:samples:)`
- Produces: `EventSegmenter.push(samples:isCandidate:) -> [RecordingAudioSegment]`
- Produces: `EventSegmenter.finish() -> [RecordingAudioSegment]`
- Consumes: 无产品依赖；纯 Swift/Foundation。

- [ ] **Step 1：写 EnergyDetector 失败测试**

```swift
func testQuietFramesDoNotTriggerButLoudFramesDo() {
    var detector = EnergyDetector()
    for _ in 0..<20 {
        XCTAssertFalse(detector.isCandidate(Array(repeating: 100, count: 1_024)))
    }
    XCTAssertTrue(detector.isCandidate(Array(repeating: 8_000, count: 1_024)))
}

func testSustainedLoudInputEventuallyAdaptsInsteadOfStayingTriggeredForever() {
    var detector = EnergyDetector()
    let results = (0..<220).map { _ in
        detector.isCandidate(Array(repeating: 8_000, count: 1_024))
    }
    XCTAssertTrue(results.prefix(160).contains(true))
    XCTAssertTrue(results.suffix(40).allSatisfy { !$0 })
}
```

- [ ] **Step 2：运行测试确认因类型不存在而失败**

Run:

```bash
xcodebuild test -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -only-testing:MinimalSleepTests/EnergyDetectorTests \
  -derivedDataPath /tmp/minimal-sleep-recording-task1 CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL，提示 `cannot find 'EnergyDetector' in scope`。

- [ ] **Step 3：实现与 Android 一致的自适应 RMS 检测**

```swift
struct EnergyDetector: Sendable {
    private var backgroundRMS: Float = 0.004
    private var consecutiveHits = 0

    mutating func isCandidate(_ samples: [Int16]) -> Bool {
        guard !samples.isEmpty else { return false }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / 32_768.0
            return partial + normalized * normalized
        } / Double(samples.count)
        let rms = Float(meanSquare.squareRoot())
        let hit = rms > max(0.012, backgroundRMS * 2.5)
        consecutiveHits = hit ? consecutiveHits + 1 : 0
        let adaptation: Float = consecutiveHits > 160 ? 0.05 : (hit ? 0.001 : 0.02)
        backgroundRMS += (rms - backgroundRMS) * adaptation
        return hit && consecutiveHits <= 160
    }
}
```

- [ ] **Step 4：写 EventSegmenter 失败测试**

使用 `sampleRate = 10` 的小型夹具验证：

```swift
func testIncludesThreeSecondsBeforeAndAfterCandidate() {
    var segmenter = EventSegmenter(sampleRate: 10, preSeconds: 3, postSeconds: 3, maxSeconds: 60)
    XCTAssertTrue(segmenter.push(samples: Array(0..<30).map(Int16.init), isCandidate: false).isEmpty)
    XCTAssertTrue(segmenter.push(samples: Array(repeating: 1_000, count: 10), isCandidate: true).isEmpty)
    let result = segmenter.push(samples: Array(repeating: 0, count: 30), isCandidate: false)
    XCTAssertEqual(result.single?.startSample, 0)
    XCTAssertEqual(result.single?.samples.count, 70)
}

func testSixtySecondSplitPreservesAllSamplesAndGroupID() {
    var segmenter = EventSegmenter(sampleRate: 10, preSeconds: 3, postSeconds: 3, maxSeconds: 60)
    let output = segmenter.push(samples: Array(repeating: 2_000, count: 1_250), isCandidate: true)
        + segmenter.finish()
    XCTAssertEqual(output.reduce(0) { $0 + $1.samples.count }, 1_250)
    XCTAssertGreaterThan(output.count, 1)
    XCTAssertEqual(Set(output.map(\.groupID)).count, 1)
}
```

在测试文件添加：

```swift
private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
```

- [ ] **Step 5：运行 EventSegmenter 测试确认失败**

Run: 与 Step 2 相同，但使用 `-only-testing:MinimalSleepTests/EventSegmenterTests`。
Expected: FAIL，提示类型不存在。

- [ ] **Step 6：实现环形前缓冲、安静后缓冲、finish 和 60 秒拆分**

实现 `RecordingAudioSegment` 为 `Equatable, Sendable`，样本游标使用 `Int64`，在满 60 秒时发出片段并为下一个片段推进 `startSample`，但保留同一个 `groupID`。不要在该文件进行磁盘 I/O。

- [ ] **Step 7：运行 Task 1 定向测试和完整 XCTest**

Run:

```bash
xcodebuild test -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -only-testing:MinimalSleepTests/EnergyDetectorTests \
  -only-testing:MinimalSleepTests/EventSegmenterTests \
  -derivedDataPath /tmp/minimal-sleep-recording-task1 CODE_SIGNING_ALLOWED=NO
```

Expected: 新增测试 PASS。随后运行完整 XCTest，Expected: 0 failures。

- [ ] **Step 8：提交 Task 1**

```bash
git add ios/MinimalSleep/Recording/EnergyDetector.swift \
  ios/MinimalSleep/Recording/EventSegmenter.swift \
  ios/MinimalSleepTests/EnergyDetectorTests.swift \
  ios/MinimalSleepTests/EventSegmenterTests.swift
git commit -m "feat: add iOS sound event segmentation"
```

---

### Task 2：录音模型与 PCM WAV 写入

**Files:**
- Create: `ios/MinimalSleep/Recording/RecordingModels.swift`
- Create: `ios/MinimalSleep/Recording/PCM16WAVWriter.swift`
- Create: `ios/MinimalSleepTests/RecordingModelsTests.swift`
- Create: `ios/MinimalSleepTests/PCM16WAVWriterTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `RecordingAudioSegment`
- Produces: `RecordingSession`, `RecordingEvent`, `RecordingPlaybackInterval`, `RecordingSessionSummary`, `RecordingIndex`
- Produces: `PCM16WAVWriting.write(samples:sampleRate:temporaryURL:finalURL:) throws`

- [ ] **Step 1：写模型 JSON 往返与 schemaVersion 测试**

```swift
func testSessionRoundTripsWithSchemaVersionOne() throws {
    let session = RecordingSession.fixture(status: .completed)
    let data = try JSONEncoder.recording.encode(session)
    let decoded = try JSONDecoder.recording.decode(RecordingSession.self, from: data)
    XCTAssertEqual(decoded, session)
    XCTAssertEqual(decoded.schemaVersion, 1)
}
```

在 `RecordingModelsTests.swift` 内定义只供测试使用的 `RecordingSession.fixture`。模型时间编码固定为 ISO-8601；不要依赖系统默认 Date 编码。

- [ ] **Step 2：运行模型测试确认失败**

Expected: FAIL，提示 `RecordingSession` 不存在。

- [ ] **Step 3：实现显式 Codable 模型**

```swift
enum RecordingSessionStatus: String, Codable, Sendable {
    case recording, completed, interrupted
}

struct RecordingEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let groupID: UUID
    let startSample: Int64
    let sampleCount: Int64
    let fileName: String
    let playbackAffected: Bool
    let createdAt: Date
}
```

`RecordingSession` 包含 `schemaVersion = 1`、会话字段、`events` 和 `playbackIntervals`。`RecordingIndex` 也包含 `schemaVersion = 1` 与 `[RecordingSessionSummary]`。

- [ ] **Step 4：写 WAV 失败测试**

```swift
func testWritesCanonicalMonoPCM16HeaderAndSamples() throws {
    let temporary = directory.appendingPathComponent("event.wav.part")
    let final = directory.appendingPathComponent("event.wav")
    try PCM16WAVWriter().write(
        samples: [-32_768, -1, 0, 1, 32_767],
        sampleRate: 16_000,
        temporaryURL: temporary,
        finalURL: final
    )
    let data = try Data(contentsOf: final)
    XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
    XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
    XCTAssertEqual(data.littleEndianUInt16(at: 22), 1)
    XCTAssertEqual(data.littleEndianUInt32(at: 24), 16_000)
    XCTAssertEqual(data.littleEndianUInt16(at: 34), 16)
    XCTAssertEqual(data.littleEndianUInt32(at: 40), 10)
    XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
}
```

在测试文件中定义读取小端整数的 `Data` helper。另写 final 已存在、空 samples、临时写入失败的测试，验证不会覆盖正式文件和不会留下 `.part`。

- [ ] **Step 5：运行 WAV 测试确认失败**

Expected: FAIL，提示 `PCM16WAVWriter` 不存在。

- [ ] **Step 6：实现小端 RIFF/WAVE 原子写入**

`PCM16WAVWriter` 必须：

1. 拒绝空 samples、非正采样率和已存在 final；
2. 创建父目录；
3. 写 44 字节 PCM header 和小端样本；
4. `FileHandle.synchronize()`；
5. 使用 `FileManager.moveItem` 发布；
6. catch 时删除 temporary。

- [ ] **Step 7：运行 Task 2 测试和完整 XCTest**

Expected: 新增模型/WAV 测试及原有测试全部 PASS。

- [ ] **Step 8：提交 Task 2**

```bash
git add ios/MinimalSleep/Recording/RecordingModels.swift \
  ios/MinimalSleep/Recording/PCM16WAVWriter.swift \
  ios/MinimalSleepTests/RecordingModelsTests.swift \
  ios/MinimalSleepTests/PCM16WAVWriterTests.swift
git commit -m "feat: add iOS recording models and WAV writer"
```

---

### Task 3：原子 RecordingStore、恢复和空间策略

**Files:**
- Create: `ios/MinimalSleep/Recording/RecordingStore.swift`
- Create: `ios/MinimalSleepTests/RecordingStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 `RecordingAudioSegment`
- Consumes: Task 2 models 与 `PCM16WAVWriting`
- Produces: `RecordingStore.sessions()`, `startSession`, `appendSegment`, `replacePlaybackIntervals`, `finishSession`, `eventFileURL`, `deleteEvent`, `deleteSession`
- Produces: `FileManagerRecordingFileSystem.applicationSupport()`

- [ ] **Step 1：定义可注入文件系统和容量协议并写失败测试**

```swift
protocol RecordingFileSystem: Sendable {
    func loadIndex() throws -> Data?
    func saveIndex(_ data: Data) throws
    func sessionIDs() throws -> [UUID]
    func loadSession(id: UUID) throws -> Data?
    func saveSession(id: UUID, data: Data) throws
    func publishWAV(sessionID: UUID, eventID: UUID, samples: [Int16], sampleRate: Int) throws -> String
    func removeWAV(sessionID: UUID, fileName: String) throws
    func removeSessionDirectory(id: UUID) throws
    func eventFileURL(sessionID: UUID, fileName: String) -> URL
    func totalRecordingBytes() throws -> Int64
    func availableCapacity() throws -> Int64
}
```

测试 `startSession` 写入 `.recording` 会话与摘要；第二次读取返回同一记录。

- [ ] **Step 2：运行测试确认 `RecordingStore` 不存在**

Expected: FAIL。

- [ ] **Step 3：实现 actor 与 1 GiB/200 MiB 边界**

```swift
enum RecordingStoreLimits {
    static let maximumTotalBytes: Int64 = 1_024 * 1_024 * 1_024
    static let minimumAvailableBytes: Int64 = 200 * 1_024 * 1_024
}

actor RecordingStore {
    func startSession(id: UUID, at: Date, timeZoneIdentifier: String) throws -> RecordingSession
    func appendSegment(
        _ segment: RecordingAudioSegment,
        to sessionID: UUID,
        playbackAffected: Bool,
        createdAt: Date
    ) throws -> RecordingEvent
}
```

每次开始和 append 前检查容量，边界值等于限制时分别拒绝和允许必须由测试明确：总量 `>= 1 GiB` 拒绝；可用空间 `< 200 MiB` 拒绝，等于 200 MiB 允许。

- [ ] **Step 4：写事务失败与恢复测试**

至少覆盖：

```swift
func testSessionSaveFailureRollsBackPublishedWAVAndDoesNotExposeEvent() async throws
func testIndexSaveFailureKeepsRecoverableSessionAndWAV() async throws
func testRecoveryRebuildsIndexAfterPreviousIndexSaveFailure() async throws
func testCorruptIndexRebuildsFromValidSessionFiles() async throws
func testStaleRecordingSessionBecomesInterruptedWithoutDeletingWAV() async throws
func testUnknownSchemaVersionIsReportedWithoutOverwritingFiles() async throws
func testDeleteEventRestoresMetadataWhenFileRemovalFails() async throws
func testDeleteSessionRemovesIndexOnlyAfterDirectoryDeletionSucceeds() async throws
```

- [ ] **Step 5：实现事务顺序和恢复**

`appendSegment` 顺序固定为：发布 WAV → 保存更新后的 session → 保存 index。session 保存失败时删除新 WAV；index 保存失败时保留包含该事件的 session 与 WAV、向调用方报告错误，并在下次初始化时从 session 重建 index。这样 index 永远只是可重建摘要，不会因为二次回滚失败而丢失已经写好的用户录音。

删除事件时先把 WAV 原子改名到同目录 `.deleting`，再保存移除事件后的 session/index，最后删除暂存文件；任何 JSON 保存失败都恢复旧 metadata 并把文件改回原名。删除会话时先从 index 移除摘要并保留旧 index 数据，目录删除失败则恢复 index。恢复流程清理能够和有效 metadata 对应的 `.deleting`/`.part`，无法判定归属的文件保持不变并报告错误。

恢复时扫描合法 `session.json`，重建 index；旧 `.recording` 改为 `.interrupted`，`endReason = "App 意外退出"`。无法解析的目录保持不变并报告 `RecordingStoreError.corruptSession(id)`。

- [ ] **Step 6：实现 FileManagerRecordingFileSystem**

根目录为 `Application Support/NightRecordings`。初始化时创建 `Sessions`，设置 `isExcludedFromBackup = true`。所有 JSON 写入 `*.part` 后使用 `replaceItemAt` 或同卷 move 实现原子发布；WAV 使用 Task 2 writer。

- [ ] **Step 7：运行 Task 3 测试、完整 XCTest 和 `git diff --check`**

Expected: 0 failures；测试临时目录不进入仓库。

- [ ] **Step 8：提交 Task 3**

```bash
git add ios/MinimalSleep/Recording/RecordingStore.swift \
  ios/MinimalSleepTests/RecordingStoreTests.swift
git commit -m "feat: persist iOS night recordings locally"
```

---

### Task 4：共享 AudioSessionController 与播放回归

**Files:**
- Create: `ios/MinimalSleep/Playback/AudioSessionController.swift`
- Create: `ios/MinimalSleepTests/AudioSessionControllerTests.swift`
- Modify: `ios/MinimalSleep/Playback/AVAudioPlayerPlaybackEngine.swift`
- Modify: `ios/MinimalSleep/Playback/AudioCoordinator.swift`
- Modify: `ios/MinimalSleepTests/AudioCoordinatorTests.swift`

**Interfaces:**
- Produces: `AudioSessionController.setPlaybackActive(_:) throws`
- Produces: `AudioSessionController.setRecordingActive(_:) throws`
- Produces: `AudioSessionController.onSafetyEvent: ((AudioSafetyEvent) -> Void)?`
- Produces: `AudioCoordinator.recordingPlaybackSnapshot`

- [ ] **Step 1：写四态会话矩阵失败测试**

使用 fake `SystemAudioSessionApplying` 记录 category、options 和 active 调用：

```swift
func testPausingPlaybackDoesNotDeactivateAnActiveRecordingSession() throws {
    let system = FakeSystemAudioSession()
    let controller = AudioSessionController(system: system, observeNotifications: false)
    try controller.setRecordingActive(true)
    try controller.setPlaybackActive(true)
    try controller.setPlaybackActive(false)
    XCTAssertEqual(system.lastCategory, .playAndRecord)
    XCTAssertTrue(system.isActive)
    XCTAssertTrue(system.lastOptions.contains(.defaultToSpeaker))
}
```

还要覆盖仅播放、仅录音、都停止，以及重复赋相同状态不重复配置。

- [ ] **Step 2：运行测试确认失败**

Expected: FAIL，类型不存在。

- [ ] **Step 3：实现会话状态机和通知映射**

```swift
enum AudioSafetyEvent: Equatable, Sendable {
    case interruptionBegan
    case oldDeviceUnavailable
}
```

`reconcile()` 严格按 spec 的四态表设置 category 和 active。只监听 interruption `.began` 与 route change `.oldDeviceUnavailable`；不处理结束通知为自动恢复。

- [ ] **Step 4：先写播放引擎回归测试，再重构 AVAudioPlayerPlaybackEngine**

新增 fake session controller，验证 `play()` 声明 playback active、`pause()`/`stop()` 只撤销 playback active。删除引擎内部 AVAudioSession 通知观察和直接 `setCategory/setActive`。

构造器改为：

```swift
init(sessionController: AudioSessionControlling)
```

- [ ] **Step 5：发布只读播放快照**

```swift
struct RecordingPlaybackSnapshot: Equatable, Sendable {
    let isPlaying: Bool
    let soundID: String
    let appVolume: Float
}
```

`AudioCoordinator.recordingPlaybackSnapshot` 根据 `playbackState`、`selectedSound.id`、`baseVolume × fadeGain` 返回当前值。测试播放、暂停、切换和淡出音量。

- [ ] **Step 6：运行定向测试和完整 XCTest**

Expected: Review Focus #1 通过，现有 33 个测试无回归。

- [ ] **Step 7：提交 Task 4**

```bash
git add ios/MinimalSleep/Playback/AudioSessionController.swift \
  ios/MinimalSleep/Playback/AVAudioPlayerPlaybackEngine.swift \
  ios/MinimalSleep/Playback/AudioCoordinator.swift \
  ios/MinimalSleepTests/AudioSessionControllerTests.swift \
  ios/MinimalSleepTests/AudioCoordinatorTests.swift
git commit -m "refactor: coordinate iOS playback and recording sessions"
```

---

### Task 5：麦克风采集、RecordingPipeline 与 NightRecordingCoordinator

**Files:**
- Create: `ios/MinimalSleep/Recording/MicrophoneCaptureEngine.swift`
- Create: `ios/MinimalSleep/Recording/RecordingPipeline.swift`
- Create: `ios/MinimalSleep/Recording/NightRecordingCoordinator.swift`
- Create: `ios/MinimalSleepTests/RecordingPipelineTests.swift`
- Create: `ios/MinimalSleepTests/NightRecordingCoordinatorTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4 的 detector、segmenter、store、audio session 和 playback snapshot
- Produces: `MicrophoneCapturing.makeFrames() throws -> AsyncThrowingStream<[Int16], Error>`
- Produces: `RecordingPipeline.consume(_:playback:)`, `finish(status:reason:)`
- Produces: `NightRecordingCoordinator.State`

- [ ] **Step 1：写 RecordingPipeline 失败测试**

用 fake store 和 `sampleRate = 10` 验证：

```swift
func testPlaybackOverlapMarksOnlyOverlappingSegment() async throws
func testPlaybackSwitchClosesOldIntervalAtCurrentSampleCursor() async throws
func testFinishFlushesSegmentAndClosesOpenPlaybackInterval() async throws
func testStoreFailureStopsFurtherConsumption() async throws
```

`consume` 签名：

```swift
func consume(_ samples: [Int16], playback: RecordingPlaybackSnapshot) async throws
```

每帧先观察 playback，再检测/切片，保证播放变化落在当前帧起点。

- [ ] **Step 2：运行 pipeline 测试确认失败**

Expected: FAIL。

- [ ] **Step 3：实现串行 RecordingPipeline actor**

actor 持有 detector、segmenter、sampleCursor、当前播放区间、已关闭区间与 sessionID。保存片段前通过半开区间交集判断：

```swift
interval.startSample < segmentEnd && interval.endSample > segment.startSample
```

每保存一个片段后发布 `onProgress(capturedSamples:eventCount:)`，UI 更新节流到不高于每秒一次。

- [ ] **Step 4：写 coordinator 权限和状态失败测试**

定义：

```swift
enum MicrophonePermission: Equatable { case notDetermined, denied, granted }
protocol MicrophonePermissionProviding {
    func status() -> MicrophonePermission
    func request() async -> Bool
}
protocol MicrophoneCapturing: AnyObject {
    func makeFrames() throws -> AsyncThrowingStream<[Int16], Error>
    func stop()
}
```

覆盖：允许、拒绝、重复 start、准备中 stop、正常 stop、frame 错误、空间错误、安全事件、不自动恢复。

- [ ] **Step 5：实现 NightRecordingCoordinator 状态机**

```swift
@MainActor
final class NightRecordingCoordinator: ObservableObject {
    enum State: Equatable {
        case stopped
        case requestingPermission
        case starting
        case recording
        case stopping
        case interrupted(String)
        case failed(String)
    }
}
```

开始顺序：权限 → store start → `setRecordingActive(true)` → capture stream → 单一消费 Task。任一步失败必须结束或回滚已创建 session。停止顺序：capture stop → 等消费 Task 结束 → pipeline finish → `setRecordingActive(false)`。

- [ ] **Step 6：实现 AVAudioEngineMicrophoneCaptureEngine**

`makeFrames()`：

1. 检查没有已有 stream；
2. 创建 AVAudioConverter 到 16 kHz mono Int16；
3. inputNode 安装 tap；
4. tap 数据复制到私有串行 conversion queue；
5. 每次 yield 恰好 1,024 样本，尾部不足在 stop 时按真实数量 yield；
6. converter、engine 或 route 错误通过 stream finish(throwing:)；
7. stop 可重复调用并移除 tap。

权限实现使用 iOS 17 `AVAudioApplication.recordPermission` 和 `AVAudioApplication.requestRecordPermission(completionHandler:)`。

- [ ] **Step 7：接入统一安全事件**

App 组装层收到 `.interruptionBegan` 或 `.oldDeviceUnavailable` 时依次调用：

```swift
audioCoordinator.handleInterruptionOrUnsafeRouteChange()
recordingCoordinator.handleSafetyEvent(event)
```

测试系统结束中断后没有 start 调用，覆盖 Review Focus #5。

- [ ] **Step 8：运行 Task 5 测试、完整 XCTest 和 Debug 模拟器构建**

模拟器不要求真实麦克风启动。Expected: fake 测试通过、App 可构建、原播放测试无回归。

- [ ] **Step 9：提交 Task 5**

```bash
git add ios/MinimalSleep/Recording/MicrophoneCaptureEngine.swift \
  ios/MinimalSleep/Recording/RecordingPipeline.swift \
  ios/MinimalSleep/Recording/NightRecordingCoordinator.swift \
  ios/MinimalSleepTests/RecordingPipelineTests.swift \
  ios/MinimalSleepTests/NightRecordingCoordinatorTests.swift
git commit -m "feat: capture iOS night sound events"
```

---

### Task 6：SwiftUI 录音控制、历史、回听和删除

**Files:**
- Create: `ios/MinimalSleep/Recording/RecordingLibrary.swift`
- Create: `ios/MinimalSleep/Views/RootTabView.swift`
- Create: `ios/MinimalSleep/Views/RecordingControlsView.swift`
- Create: `ios/MinimalSleep/Views/RecordingHistoryView.swift`
- Create: `ios/MinimalSleepTests/RecordingLibraryTests.swift`
- Modify: `ios/MinimalSleep/Views/HomeView.swift`
- Modify: `ios/MinimalSleep/App/MinimalSleepApp.swift`

**Interfaces:**
- Consumes: Task 3 store、Task 4 AudioCoordinator/AudioSessionController、Task 5 coordinator
- Produces: 用户可操作的今晚/记录界面
- Produces: `RecordingLibrary.reload`, `play`, `stopPlayback`, `deleteEvent`, `deleteSession`

- [ ] **Step 1：写 RecordingLibrary 行为失败测试**

覆盖：加载摘要、选择会话、回听前暂停助眠声、回听结束清状态、删除正在回听片段先 stop、录音中拒绝删除、错误转中文文案。

```swift
func testPlayingEventPausesSleepSoundAndDoesNotAutoResume() async throws
func testDeletingPlayingEventStopsPlayerBeforeStoreDelete() async throws
func testRecordingDisablesPlaybackAndDeletion() async throws
```

- [ ] **Step 2：实现 RecordingLibrary**

使用 `@MainActor ObservableObject` 包装 store actor。事件回听使用独立 `AVAudioPlayer`，开始前调用 `AudioCoordinator.pause()`，通过共享 `AudioSessionController.setPlaybackActive(true)` 激活会话；完成或停止后撤销，不自动恢复助眠声。

- [ ] **Step 3：写 RootTabView 和记录控制区**

```swift
TabView {
    HomeView(...)
        .tabItem { Label("今晚", systemImage: "moon.stars") }
    RecordingHistoryView(library: recordingLibrary, coordinator: recordingCoordinator)
        .tabItem { Label("记录", systemImage: "waveform") }
}
```

`RecordingControlsView` 显示开始/结束按钮、状态、`capturedSamples / 16_000` 时长、片段数、只保存在本机和播放干扰提示。按钮有明确 accessibility label。

- [ ] **Step 4：实现记录列表和详情**

会话列表：开始时间、有效时长、片段数、状态。详情：会话内开始秒数、片段秒数、干扰标记、回听/停止、删除。录音进行期间禁用回听和删除。空状态写“尚无记录”；没有片段写“没有保存的片段；这不能证明整晚安静”。

- [ ] **Step 5：在 MinimalSleepApp 只组装一份共享依赖**

构造顺序固定：

```text
AudioSessionController
→ AVAudioPlayerPlaybackEngine
→ AudioCoordinator
→ FileManagerRecordingFileSystem / RecordingStore
→ MicrophoneCaptureEngine / NightRecordingCoordinator
→ RecordingLibrary
→ RootTabView
```

禁止 View 自己创建第二个 recorder、store 或 audio session controller。

- [ ] **Step 6：运行 RecordingLibrary 测试、完整 XCTest 和模拟器启动**

Run full XCTest；然后 build/install/launch iPhone 18 Pro 模拟器。检查两个标签、今晚原功能、录音区域、记录空状态和 About 入口均可见。模拟器不记录“麦克风通过”。

- [ ] **Step 7：提交 Task 6**

```bash
git add ios/MinimalSleep/Recording/RecordingLibrary.swift \
  ios/MinimalSleep/Views/RootTabView.swift \
  ios/MinimalSleep/Views/RecordingControlsView.swift \
  ios/MinimalSleep/Views/RecordingHistoryView.swift \
  ios/MinimalSleep/Views/HomeView.swift \
  ios/MinimalSleep/App/MinimalSleepApp.swift \
  ios/MinimalSleepTests/RecordingLibraryTests.swift
git commit -m "feat: add iOS recording controls and history"
```

---

### Task 7：权限、版本、关于页面与 CI 门禁

**Files:**
- Modify: `ios/MinimalSleep/Info.plist`
- Modify: `ios/MinimalSleep.xcodeproj/project.pbxproj`
- Modify: `ios/MinimalSleep/Views/AboutView.swift`
- Create: `ios/MinimalSleepTests/AppVersionTests.swift`
- Modify: `.github/workflows/ios-build.yml`

**Interfaces:**
- Consumes: Task 6 UI
- Produces: Bundle 版本显示、麦克风说明、CI 静态门禁

- [ ] **Step 1：写 Bundle 版本与权限失败测试**

```swift
func testBundleDeclaresVersionBuildMicrophoneAndBackgroundAudio() throws {
    let bundle = Bundle.main
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "0.5.0")
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, "2")
    XCTAssertEqual(
        bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
        "极简睡眠只在你主动开始夜间记录后使用麦克风，并仅在本机保存声音触发片段。"
    )
    XCTAssertTrue((bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true)
}
```

Expected before implementation: version/microphone assertions FAIL。

- [ ] **Step 2：更新 Info.plist 和两套 target 版本**

在 Debug 与 Release 的 MinimalSleep target 中只修改：

```text
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 0.5.0;
```

不得加入 `DEVELOPMENT_TEAM`、证书或描述文件字段。Android Gradle 文件不得变化。

- [ ] **Step 3：更新 AboutView**

从 Bundle 读取 short version/build，显示 `版本 0.5.0 (2) · 开发预览`。隐私文案改为：主动开始后使用麦克风、只保存触发片段、只在本机、播放可能干扰、删除不等于安全擦除。资源文案把旧“无损 PCM”改为当前 AAC/M4A 派生资源。

- [ ] **Step 4：在 CI 包检查中加入版本和权限断言**

在 `Verify and package simulator app` 的 `app` 路径确定后加入：

```bash
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" = '0.5.0'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" = '2'
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$app/Info.plist")"
/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes' "$app/Info.plist" | grep -q audio
```

- [ ] **Step 5：验证 Android 版本未改**

Run:

```bash
git diff main...HEAD -- app/build.gradle.kts
test "$(sed -n 's/.*versionCode = //p' app/build.gradle.kts | tr -d ' ')" = '5'
grep -q 'versionName = "0.4.0-dev"' app/build.gradle.kts
```

Expected: diff 为空；两条检查退出 0。

- [ ] **Step 6：运行版本测试、完整 XCTest、Release 构建和包检查**

Expected: 所有断言通过；App 包仍含两段 M4A 与三段 WAV，旧两个雨声 WAV 不存在。

- [ ] **Step 7：提交 Task 7**

```bash
git add ios/MinimalSleep/Info.plist \
  ios/MinimalSleep.xcodeproj/project.pbxproj \
  ios/MinimalSleep/Views/AboutView.swift \
  ios/MinimalSleepTests/AppVersionTests.swift \
  .github/workflows/ios-build.yml
git commit -m "feat: version iOS recording preview"
```

---

### Task 8：文档、整体验证、推送与真机短测

**Files:**
- Modify: `README.md`
- Modify: `docs/ios-development.md`
- Modify: `docs/ios-progress.md`
- Modify: `docs/ios-validation.md`

**Interfaces:**
- Consumes: Tasks 1–7 的真实测试结果
- Produces: 可复现构建说明和准确验证记录

- [ ] **Step 1：更新开发说明**

记录：准备 M4A、运行 XCTest、无签名模拟器构建、Personal Team 真机构建、录音文件私有位置、禁止提交录音、如何安全覆盖安装。明确模拟器不能证明麦克风或锁屏录音。

- [ ] **Step 2：更新 README 与进度**

README 的 iOS 状态增加夜间声音片段录音、记录列表、回听和删除；限制部分写能量检测未经校准、没有分类、播放会干扰、没有片段不代表安静。`docs/ios-progress.md` 记录实际完成项与仍未测项目。

- [ ] **Step 3：执行完整本地门禁**

```bash
/opt/homebrew/bin/python3.12 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
xcodebuild test -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -derivedDataPath /tmp/minimal-sleep-recording-final-tests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/minimal-sleep-recording-final-release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
git diff --check
git status --short
```

Expected: 6 个 Python 测试通过；完整 XCTest 0 failures；Release `BUILD SUCCEEDED`；只有计划内文件变化和被忽略的 M4A。

- [ ] **Step 4：检查隐私、签名和录音泄漏**

```bash
git diff main...HEAD -- ios/MinimalSleep.xcodeproj/project.pbxproj | rg 'DEVELOPMENT_TEAM|PROVISIONING_PROFILE|CODE_SIGN_IDENTITY' && exit 1 || true
git ls-files | rg 'NightRecordings|\.wav\.part$|recordings/' && exit 1 || true
git status --ignored --short | rg 'rain-0[14]\.m4a'
```

Expected: 前两条没有敏感或录音匹配；最后一条显示两个生成 M4A 被忽略。

- [ ] **Step 5：提交文档**

```bash
git add README.md docs/ios-development.md docs/ios-progress.md docs/ios-validation.md
git commit -m "docs: explain iOS night recording preview"
```

- [ ] **Step 6：请求整分支代码审查并修复高优先级问题**

审查范围为 `main...codex/ios-night-recording`，重点检查实时音频线程、并发顺序、文件事务、音频会话、隐私、版本和用户数据保留。修复后重新运行 Step 3。

- [ ] **Step 7：推送分支并等待两条 CI**

```bash
git push -u origin codex/ios-night-recording
```

等待 Android APK 与 iOS Simulator App。记录运行 URL、结论、测试数量、iOS Artifact 名称、大小和摘要。失败时只修复证据指向的问题，禁止放宽清单或资源检查。

- [ ] **Step 8：使用 Personal Team 构建并覆盖安装真机**

在不提交本地签名变化的工作区构建目标设备 `00008150-001C036A1E38401C`。使用 `xcrun devicectl device install app` 覆盖安装，不卸载 App；安装后确认既有导入音频仍在。

- [ ] **Step 9：执行真机基础录音验证**

按 spec 顺序执行：权限允许/拒绝、仅录音、同时播放、锁屏 30 分钟、中断/耳机断开、回听/删除、覆盖安装保留。只使用用户同意的短测试声音；不读取、复制或上传私人夜间录音。

记录以下非内容证据：设备/系统、开始结束时间、有效样本时长、片段数量、文件大小、会话状态、干扰标记、操作结果和用户听感。

- [ ] **Step 10：把真实 CI 和真机结果写入验证文档并提交**

未执行的项目继续写“未测”。若只完成短测，8 小时整夜仍保持未完成。

```bash
git add docs/ios-progress.md docs/ios-validation.md
git commit -m "docs: record iOS recording validation"
git push
```

- [ ] **Step 11：最终验证**

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/codex/ios-night-recording
git diff --check main...HEAD
```

Expected: 分支除用户明确保留的本地签名设置和忽略资源外干净；HEAD 与远端一致；本轮所有已声称测试都有日志或 CI 证据。
