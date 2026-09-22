# 开发与构建环境交接

## 新电脑首次构建

Git 仓库含源码、三段原创生成 WAV、两段经作者 CC BY 4.0 授权的雨声剪辑、Gradle Wrapper 和依赖版本声明。它**不包含** JDK、Android SDK、Gradle 缓存、构建输出或 APK；这些体积较大、与平台有关，已由 `.gitignore` 排除。新开发者需要 JDK 17、Android SDK Platform API 36、Build Tools 35.0.0。运行 `./gradlew testDebugUnitTest lintDebug assembleDebug`（Windows 用 `./gradlew.bat`）时，Wrapper 和 Gradle 会首次下载 Gradle 与 Maven 依赖；速度取决于网络和已有缓存。Android App 安装后离线运行，无网络权限。

## 此 Windows 工作区快速复用

先检查 `.tools/` 是否仍在。当前已核验的相对路径：

| 内容 | 路径 |
|---|---|
| JDK 17 | `.tools/jdk/jdk17.0.20_10` |
| Android SDK API 36 与 Build Tools 35 | `.tools/android-sdk-ready` |
| Gradle 8.13 | `.tools/gradle/gradle-8.13` |
| Maven/Gradle 缓存 | `.tools/gradle-home` |

在仓库根目录的 PowerShell 中：

```powershell
$env:JAVA_HOME = (Resolve-Path '.tools/jdk/jdk17.0.20_10').Path
$env:ANDROID_HOME = (Resolve-Path '.tools/android-sdk-ready').Path
$env:GRADLE_USER_HOME = (Join-Path (Resolve-Path '.tools').Path 'gradle-home')
$env:MINIMAL_SLEEP_MAVEN_PROXY = 'http://127.0.0.1:8765/m2'
& '.tools/gradle/gradle-8.13/bin/gradle.bat' --offline --no-daemon --console plain lintDebug testDebugUnitTest assembleDebug
```

2026-09-20 实测退出码 0，`.tools/offline-build-proxy-cache-check.log` 显示 `BUILD SUCCESSFUL in 41s`，58 个任务、47 个已是最新。`--offline` 禁止网络访问，**不需要启动本地代理**。仍设置 `MINIMAL_SLEEP_MAVEN_PROXY` 是因为现有 Gradle 缓存按当初下载时的仓库 URL 索引；移除该变量后同一缓存离线解析 Kotlin kapt 插件失败。新电脑不应照搬这个变量，除非确实启动了本地代理。

如果此工作区新增依赖、缓存缺项且 Java 访问 Maven 出现 TLS 问题，可在另一个终端运行 `python tools/dev_maven_proxy.py`，保留上述代理环境变量并去掉 `--offline`。它仅绑定 `127.0.0.1:8765` 并从公开官方 Maven 仓库转发依赖。普通网络可直接使用 Wrapper 与 `settings.gradle.kts` 的官方仓库配置。

首次工具下载和失败排查、APK 签名与真机测试证据见 `docs/validation.md`。当前公开的调试 APK 在 [GitHub 预发布页](https://github.com/Resker666/minimal-sleep/releases/tag/v0.2.0-preview.1)；它不在 Git 历史中。任何新 APK 的签名、大小、哈希与真机表现需重新验证。
