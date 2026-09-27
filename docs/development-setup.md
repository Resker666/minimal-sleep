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
& '.tools/gradle/gradle-8.13/bin/gradle.bat' --offline --no-daemon --console plain '-Pkotlin.compiler.execution.strategy=in-process' lintDebug testDebugUnitTest assembleDebug
```

2026-09-20 的旧缓存按本地代理 URL 索引，故当时离线构建仍需设置 `MINIMAL_SLEEP_MAVEN_PROXY`；这是旧缓存的特殊情况。2026-09-25 此工作区原 `.tools/` 已缺失，检查后重新恢复工具与官方仓库依赖缓存，随后**不设置代理变量**也能用上述命令离线完成 Lint、24 个单元测试和 APK 构建。`--offline` 禁止 Gradle 网络访问；若 `.tools/` 再次缺失，先查找已有工具或缓存，不要照搬旧路径而直接重复下载。

如果此工作区新增依赖、缓存缺项且 Java 访问 Maven 出现 TLS 问题，可在另一个终端运行 `python tools/dev_maven_proxy.py`，保留上述代理环境变量并去掉 `--offline`。它仅绑定 `127.0.0.1:8765` 并从公开官方 Maven 仓库转发依赖。普通网络可直接使用 Wrapper 与 `settings.gradle.kts` 的官方仓库配置。

首次工具下载和失败排查、APK 签名与真机测试证据见 `docs/validation.md`。当前公开的调试 APK 在 [GitHub 预发布页](https://github.com/Resker666/minimal-sleep/releases/tag/v0.2.0-preview.1)；它不在 Git 历史中。任何新 APK 的签名、大小、哈希与真机表现需重新验证。

## GitHub Actions 构建

`.github/workflows/android-apk.yml` 在 `main`、`codex/**` 推送时自动运行，也定义了手动触发入口。GitHub 托管的 Ubuntu 运行器安装 JDK 17、Python 3.12、Android SDK API 36、Build Tools 35.0.0 与 FFmpeg；Gradle Wrapper 使用仓库指定的 8.13 版本，并从官方仓库下载依赖。新运行器不使用本机 `.tools/` 或 `MINIMAL_SLEEP_MAVEN_PROXY`。首次运行仍需下载工具和依赖，后续 Gradle 缓存可缩短构建时间。

工作流依次运行 Python 音频工具测试、`lintDebug testDebugUnitTest assembleDebug`，只在成功后上传 APK 与 SHA-256 文件到该次运行的 **Artifacts**。登录 GitHub 后可下载 ZIP 形式的临时构建产物；工作流不会自动创建 Release。云端使用运行器生成的调试签名，不配置或上传固定签名密钥；它与已有本机 APK 的签名不一致，不能覆盖安装。固定签名需要另行设计密钥保管和发布流程，见 [开发进度](progress.md)。
