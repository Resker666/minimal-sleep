# 第三方来源与许可证

本项目原创 Kotlin、Swift、Python 源码及三段生成 WAV 按根目录 `LICENSE` 的 Apache-2.0 条款提供。两段 Resker666 录制雨声音轨的剪辑 `rain-01.ogg`、`rain-04.ogg` 及其 iOS AAC/M4A 派生文件按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 提供；署名 **Resker666**，修改为各取第 600–900 秒、尾首交叉淡化 2 秒并转码 Ogg，第二段另降低至 0.75 倍增益，iOS 派生步骤将 Ogg 转码为 128 kbps AAC/M4A，不再次裁剪、调整增益或重采样。用户于 2026-09-22 确认本人持有两段音轨的权利并作此授权。音频处理方式及 SHA-256 见 `docs/assets.md`、`assets-manifest.csv` 和 `ios/MinimalSleep/Resources/audio-derivations.json`。内置 Google YAMNet Lite v1 模型及标签，来源、哈希与局限见 `docs/model-assets.md`；模型页标示 Apache-2.0。用户自行导入的手机本地音频只留在 App 私有目录，不随源码、APK 或 iOS App 分发。

| 直接依赖 | 固定版本 | 来源 | 许可证 | 用途 |
|---|---|---|---|---|
| AndroidX Compose BOM、Material 3 | 2026.05.00（Material 3 1.4.0） | [AndroidX](https://developer.android.com/jetpack/androidx/releases/compose) | [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0) | 界面 |
| AndroidX Activity Compose | 1.13.0 | [AndroidX](https://developer.android.com/jetpack/androidx/releases/activity) | Apache-2.0 | Activity 与权限界面 |
| AndroidX Media3 ExoPlayer、Session | 1.11.1 | [AndroidX Media3](https://developer.android.com/jetpack/androidx/releases/media3) | Apache-2.0 | 后台播放与媒体会话 |
| AndroidX Room Runtime、KTX、Compiler | 2.8.5 | [AndroidX Room](https://developer.android.com/jetpack/androidx/releases/room) | Apache-2.0 | 本地数据库；Compiler 仅构建时使用 |
| Kotlin 标准库、Compose Compiler、kapt | 2.3.21 | [Kotlin](https://github.com/JetBrains/kotlin) | Apache-2.0 | 语言运行库及构建 |
| Kotlin Coroutines Android | 1.10.2 | [kotlinx.coroutines](https://github.com/Kotlin/kotlinx.coroutines) | Apache-2.0 | 后台查询与界面协程 |
| Google AI Edge LiteRT、LiteRT API | 1.4.2 | [Google Maven](https://maven.google.com/web/index.html#com.google.ai.edge.litert:litert) | Apache-2.0（POM 声明） | 设备内 TFLite 推理 |
| Google YAMNet classification TFLite | v1 | [Google 模型页](https://www.kaggle.com/models/google/yamnet/tfLite/classification-tflite/1) | Apache-2.0（模型页标示） | 疑似声音分类，521 个标签 |
| JUnit 4 | 4.13.2 | [JUnit 4](https://github.com/junit-team/junit4) | EPL-1.0 | 仅单元测试，不随 APK 打包 |

构建工具 Android Gradle Plugin 8.13.2、Gradle 8.13、Android SDK 36、Build Tools 35 与 JDK 17 仅用于生成 APK。AndroidX/Media3 还会传递引入其他 Apache-2.0 许可组件（包括 Guava）；构建时以 Gradle 解析的依赖图和各组件原始许可证为准。其余未经授权的本地试听素材和参考仓库代码未进入 APK。
