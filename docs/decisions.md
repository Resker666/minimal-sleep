# 技术决策

## 2026-09-20：新建 Kotlin + Compose 工程

原仓库只有 `README.md`（内容为 `# minimal-sleep`），Git `main` 干净，无 `AGENTS.md`。保留 README 原内容，不 fork 参考项目。

只读核查 [FOSS Snore Detector](https://github.com/elgrande73/FOSS-snore-detector-android-app)：其仓库显示 Apache-2.0、AudioRecord、Room、Compose 和前台服务；[架构文档](https://github.com/elgrande73/FOSS-snore-detector-android-app/blob/main/ARCHITECTURE.md) 描述播放时抑制触发事件，并称 AEC/NS 可清除扬声器反馈。本项目要求同时播放时保留采集、播放区间和干扰标记，因此不直接 fork，也不复制代码。其构建与真机表现未在本机验证。[AudioRecorder](https://github.com/Dimowner/AudioRecorder) 只作交互与录音思路参考，不复制代码或资源。

首版使用原生 Android API、Jetpack Compose 和后续明确锁版的依赖。内置声音由仓库脚本自生成，模型权重只有在来源、许可证、哈希及本机推理都核实后才会加入。应用运行时不请求 `INTERNET` 权限。源码计划以 Apache-2.0 发布；尚未公开发布。

构建版本依据：[AGP 8.13.2 与 Gradle 8.13/JDK 17/API 36.1 兼容表](https://developer.android.com/build/releases/agp-8-13-0-release-notes)、[Compose BOM 映射](https://developer.android.com/develop/ui/compose/bom/bom-mapping)、[Kotlin 2.3.21 发布记录](https://kotlinlang.org/docs/releases.html)。最新 Compose BOM 2026.09.00 解析到 Compose 1.12.1，AAR 元数据要求 AGP 9.1 和 compileSdk 37，实测 `checkDebugAarMetadata` 拒绝本工程的 AGP 8.13.2/API 36。工程改锁 Compose BOM 2026.05.00（Compose 1.11.1、Material3 1.4.0）；直接检查 `foundation-android:1.11.1` AAR 元数据要求的最低 AGP 8.6/API 35，最终以完整构建结果为准。

## 2026-09-20：播放、录音与分类边界

后台播放采用 [AndroidX Media3 的 MediaSessionService](https://developer.android.com/media/media3/session/background-playback)，固定 1.11.1；录音使用 Android `AudioRecord`，固定单一采集者和 microphone 前台服务。夜间记录元数据采用 [Room 2.8.5](https://developer.android.com/jetpack/androidx/releases/room)，仅保存私有目录内 WAV 文件名。Room 版本 1 schema 入库；后续迁移必须显式编写，不使用破坏性回退。三者均按 AndroidX 的 Apache-2.0 许可使用，未复制参考仓库实现。

能量触发器只判断相对电平并保留上下文，不能区分鼾声、语音或环境声音，因此当前统一显示“普通声音”。[官方 YAMNet 说明](https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/README.md)和 [Google 音频分类文档](https://developers.google.com/edge/litert/libraries/task_library/audio_classifier)是下一阶段调研来源；权重文件、标签、再分发许可、SHA-256 与独立评估样本尚未一并核验，没有内置模型或伪造分类。对播放声仅保存区间和重叠干扰标记，未启用声学回声消除，也未声称精确消除。
