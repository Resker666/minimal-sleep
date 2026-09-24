# iOS 音频生成流水线与真机可靠性实施计划

> **给执行代理：** 必须使用 `superpowers:executing-plans` 按任务逐项实施；如果用户明确选择多代理执行，改用 `superpowers:subagent-driven-development`。所有步骤使用复选框记录真实完成状态。

**目标：** 让全新克隆能够从两个已跟踪 Ogg 生成 iOS 雨声 WAV，让 CI 拒绝缺少任意内置声音的 App，并完成当前播放版的分阶段真机可靠性验证。

**架构：** Git 只保存 Ogg 源音频、生成脚本、派生清单和三段较小 WAV。本地准备流程与 GitHub Actions 在 Xcode 测试和构建前生成两个大型 PCM WAV；CI 再检查 Git 跟踪状态、清单一致性和 App 包内五个声音。真机测试按短测、循环与定时、路由与导入、整夜播放依次进行，只记录实际证据。

**技术栈：** Python 3.12、FFmpeg、GitHub Actions、Swift/XCTest、Xcode 27、AVFoundation、iOS 27 真机。

**规格：** `docs/superpowers/specs/2026-09-24-ios-audio-pipeline-device-reliability-design.md`

## 全局约束

- 不再次重写 Git 历史。
- 不提交 `ios/MinimalSleep/Resources/rain-01.wav`、`rain-04.wav` 或 `.rain-*.transcoding.wav`。
- 不提交 Personal Team ID、证书、密钥、描述文件、Apple 账号数据或 Xcode 用户数据。
- 不读取、复制、上传或提交手机夜间录音和用户私人音频。
- 保持 App 离线；本阶段不加入录音、分类、账号、分析 SDK 或联网下载。
- 只写真实运行过的测试结果；模拟器、无签名设备构建和真机测试必须明确区分。
- 当前主工作区的 `project.pbxproj` 和 `Info.plist` 本地修改不得带入隔离分支。
- Git 历史清理已完成；任何后续操作只使用普通提交和正常分支推送。

## 审查重点

1. **干净 checkout 缺少两个雨声 WAV：** Task 2 的 CI 准备步骤必须在 XCTest 前生成，Task 3 检查 App 包内五个声音。
2. **生成文件重新进入 Git：** Task 1 验证三个忽略路径，Task 2 用 `git ls-files` 阻止两个最终 WAV 被跟踪。
3. **FFmpeg 输出与派生清单漂移：** Task 2 和 Task 3 都运行清单 diff 与固定 SHA-256 检查。
4. **Personal Team 配置泄漏：** 每个提交前检查暂存 diff；Task 6 真机 Run 后恢复 Xcode 自动写入的工程修改。
5. **把有限验证写成普遍可靠：** Task 6 至 Task 8 分别记录设备、时长、路由、充电状态和未测项目，不从单次结果扩大结论。

---

### Task 1：修正生成音频的 Git 忽略规则

**文件：**

- 修改：`.gitignore:13-36`

**接口：**

- 输入：`tools/prepare_ios_audio.py` 使用的两个最终路径和 `.rain-*.transcoding.wav` 临时路径。
- 输出：三个路径类别均被 Git 忽略，其他三段 iOS WAV 继续由 Git 跟踪。

- [ ] **Step 1：记录修改前的失败行为**

运行：

```bash
git check-ignore -v --no-index ios/MinimalSleep/Resources/rain-01.wav
git check-ignore -v --no-index ios/MinimalSleep/Resources/rain-04.wav
git check-ignore -v --no-index ios/MinimalSleep/Resources/.rain-01.transcoding.wav
```

预期：前两个路径命中现有第 35、36 行；临时路径退出码为 1，因为第 15 行的 iOS WAV 例外把它重新放行。这是本任务要修复的基线。

- [ ] **Step 2：替换末尾忽略规则**

把 `.gitignore` 最后部分改为：

```gitignore
# Generated iOS audio. Rebuild with tools/prepare_ios_audio.py.
/ios/MinimalSleep/Resources/rain-01.wav
/ios/MinimalSleep/Resources/rain-04.wav
/ios/MinimalSleep/Resources/.rain-*.transcoding.wav
```

保留第 13 至 17 行现有全局规则和三个已跟踪的小型 iOS WAV。

- [ ] **Step 3：验证最终文件和临时文件均被忽略**

运行：

```bash
git check-ignore -v --no-index ios/MinimalSleep/Resources/rain-01.wav
git check-ignore -v --no-index ios/MinimalSleep/Resources/rain-04.wav
git check-ignore -v --no-index ios/MinimalSleep/Resources/.rain-01.transcoding.wav
git check-ignore -v --no-index ios/MinimalSleep/Resources/.rain-04.transcoding.wav
```

预期：四条命令都命中新加入的根路径规则。

- [ ] **Step 4：确认跟踪范围没有扩大或缩小**

运行：

```bash
test -z "$(git ls-files -- ios/MinimalSleep/Resources/rain-01.wav ios/MinimalSleep/Resources/rain-04.wav)"
git ls-files --error-unmatch \
  ios/MinimalSleep/Resources/heavy_rain.wav \
  ios/MinimalSleep/Resources/ocean_waves.wav \
  ios/MinimalSleep/Resources/white_noise.wav
git diff --check
```

预期：两个生成 WAV 没有输出；三个小型 WAV 都由 `git ls-files` 输出；`git diff --check` 退出码 0。

- [ ] **Step 5：提交忽略规则**

```bash
git add .gitignore
git diff --cached --check
git commit -m "chore: protect generated iOS audio"
```

---

### Task 2：让 iOS CI 生成并验证完整音频资源

**文件：**

- 修改：`.github/workflows/ios-build.yml:3-124`

**接口：**

- 输入：两个 Ogg、`tools/prepare_ios_audio.py`、`tools/test_prepare_ios_audio.py`、`assets-manifest.csv` 和 `audio-derivations.json`。
- 输出：进入 XCTest 前生成两个 WAV；上传前确认 App 包含五个内置声音。

- [ ] **Step 1：建立修改前会失败的静态断言**

运行：

```bash
rg -n "prepare_ios_audio|rain-01.ogg|rain-04.ogg|test_prepare_ios_audio|rain-01.wav|rain-04.wav" \
  .github/workflows/ios-build.yml
```

预期：当前工作流没有这些准备和验证内容，命令退出码为 1。

- [ ] **Step 2：扩大 push 和 pull_request 路径触发范围**

在两个 `paths:` 列表中，除现有 `ios/**` 和工作流自身外加入：

```yaml
      - 'app/src/main/assets/local-sounds/rain-01.ogg'
      - 'app/src/main/assets/local-sounds/rain-04.ogg'
      - 'tools/prepare_ios_audio.py'
      - 'tools/test_prepare_ios_audio.py'
      - 'assets-manifest.csv'
```

- [ ] **Step 3：在 checkout 后加入 Python 和 FFmpeg 环境**

加入：

```yaml
      - name: Set up Python 3.12
        uses: actions/setup-python@v7
        with:
          python-version: '3.12'

      - name: Install FFmpeg
        run: |
          brew install ffmpeg
          ffmpeg -version | head -n 1
```

这两个步骤放在 “Show Xcode environment” 之前，保证后续准备命令使用明确的 Python 主版本并留下 FFmpeg 版本证据。

- [ ] **Step 4：加入音频测试、生成和来源一致性检查**

在选择模拟器之前加入：

```yaml
      - name: Prepare generated iOS audio
        run: |
          set -euo pipefail

          tracked_generated="$(git ls-files -- \
            ios/MinimalSleep/Resources/rain-01.wav \
            ios/MinimalSleep/Resources/rain-04.wav)"
          test -z "$tracked_generated"

          git check-ignore -q --no-index ios/MinimalSleep/Resources/rain-01.wav
          git check-ignore -q --no-index ios/MinimalSleep/Resources/rain-04.wav
          git check-ignore -q --no-index ios/MinimalSleep/Resources/.rain-01.transcoding.wav

          python -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
          python tools/prepare_ios_audio.py --ffmpeg "$(command -v ffmpeg)"

          test -s ios/MinimalSleep/Resources/rain-01.wav
          test -s ios/MinimalSleep/Resources/rain-04.wav

          git diff --exit-code -- \
            assets-manifest.csv \
            ios/MinimalSleep/Resources/audio-derivations.json
```

该步骤只生成被忽略文件。清单发生变化、路径被跟踪、忽略规则失效或转码失败都会阻止后续测试。

- [ ] **Step 5：在打包前验证五个声音**

在 `Verify and package simulator app` 的 `test -s "$app/MinimalSleep"` 后加入：

```bash
test -s "$app/rain-01.wav"
test -s "$app/rain-04.wav"
test -s "$app/heavy_rain.wav"
test -s "$app/ocean_waves.wav"
test -s "$app/white_noise.wav"
```

- [ ] **Step 6：验证 YAML 和关键防护存在**

运行：

```bash
ruby -e 'require "yaml"; YAML.parse_file(".github/workflows/ios-build.yml"); puts "yaml ok"'
rg -n "Set up Python 3.12|Install FFmpeg|Prepare generated iOS audio" \
  .github/workflows/ios-build.yml
rg -n "rain-01.ogg|rain-04.ogg|test_prepare_ios_audio.py|git ls-files|git check-ignore" \
  .github/workflows/ios-build.yml
rg -n 'test -s "\$app/(rain-01|rain-04|heavy_rain|ocean_waves|white_noise)\.wav"' \
  .github/workflows/ios-build.yml
git diff --check
```

预期：Ruby 输出 `yaml ok`，三个 `rg` 都找到预期内容，diff 检查退出码 0。

- [ ] **Step 7：提交 CI 修改**

```bash
git add .github/workflows/ios-build.yml
git diff --cached --check
git diff --cached | rg -n "DEVELOPMENT_TEAM|PRIVATE KEY|mobileprovision" && exit 1 || true
git commit -m "ci: generate iOS audio before build"
```

---

### Task 3：在 Mac 上执行完整的本地生成、测试和打包验证

**文件：**

- 读取：`tools/prepare_ios_audio.py`
- 读取：`ios/MinimalSleep.xcodeproj`
- 生成但不跟踪：`ios/MinimalSleep/Resources/rain-01.wav`
- 生成但不跟踪：`ios/MinimalSleep/Resources/rain-04.wav`
- 构建输出：`/tmp/minimal-sleep-ios-reliability-*`

**接口：**

- 输入：Task 1 的忽略规则、Task 2 的 CI 命令和本机 FFmpeg 9.0.2。
- 输出：两个固定哈希 WAV、通过的 XCTest、包含五个声音的 Release 模拟器 App。

- [ ] **Step 1：确认隔离 worktree 起点和工具**

运行：

```bash
git status --short --branch
python3 --version
ffmpeg -version | head -n 1
test ! -e ios/MinimalSleep/Resources/rain-01.wav
test ! -e ios/MinimalSleep/Resources/rain-04.wav
```

预期：只有本计划实施产生的已知源码修改；Python 可执行；FFmpeg 为可用版本；两个派生 WAV 尚不存在。

- [ ] **Step 2：运行音频工具测试并生成 WAV**

```bash
python3 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
python3 tools/prepare_ios_audio.py --ffmpeg "$(command -v ffmpeg)"
```

预期：4 个测试通过；脚本输出两个文件的 SHA-256。

- [ ] **Step 3：核对固定哈希、忽略状态和派生清单**

```bash
printf '%s  %s\n' \
  bdfda7d0dec01eaf65eb006bc2f09d1276ec11ac601120d28e7797c35e958269 \
  ios/MinimalSleep/Resources/rain-01.wav | shasum -a 256 -c -

printf '%s  %s\n' \
  3f66e5b609802376af96221911f50d474ef42239b449c80c22c911c742a5b8dc \
  ios/MinimalSleep/Resources/rain-04.wav | shasum -a 256 -c -

git check-ignore -v ios/MinimalSleep/Resources/rain-01.wav
git check-ignore -v ios/MinimalSleep/Resources/rain-04.wav
test -z "$(git ls-files -- ios/MinimalSleep/Resources/rain-01.wav ios/MinimalSleep/Resources/rain-04.wav)"
git diff --exit-code -- assets-manifest.csv ios/MinimalSleep/Resources/audio-derivations.json
```

预期：两个哈希均显示 `OK`；两个文件被忽略且未跟踪；两个清单没有 diff。

- [ ] **Step 4：取得当前可用模拟器并运行 XCTest**

先运行：

```bash
xcrun simctl list devices available
```

在当前机器使用实际可用的 iPhone 18 Pro：

```bash
xcodebuild \
  -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=75FA9690-7229-4F85-96C1-284AD9262383' \
  -derivedDataPath /tmp/minimal-sleep-ios-reliability-tests \
  -resultBundlePath /tmp/minimal-sleep-ios-reliability-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  test
```

预期：`** TEST SUCCEEDED **`，31 个测试、0 失败。若设备 UUID 变化，只使用前一步实际列出的可用 iPhone UUID，并把实际值写入验证文档。

- [ ] **Step 5：构建 Release 模拟器 App 并检查五个声音**

```bash
xcodebuild \
  -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/minimal-sleep-ios-reliability-release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

app=/tmp/minimal-sleep-ios-reliability-release/Build/Products/Release-iphonesimulator/MinimalSleep.app
test -s "$app/MinimalSleep"
test -s "$app/rain-01.wav"
test -s "$app/rain-04.wav"
test -s "$app/heavy_rain.wav"
test -s "$app/ocean_waves.wav"
test -s "$app/white_noise.wav"
```

预期：`** BUILD SUCCEEDED **`，六条 `test -s` 均退出 0。

- [ ] **Step 6：确认生成文件没有进入待提交列表**

```bash
git status --short
git diff --check
```

预期：`git status` 只显示 Task 1、Task 2 和后续文档的已知修改，不显示两个大型 WAV。

---

### Task 4：更新开发说明并记录本地验证证据

**文件：**

- 修改：`docs/ios-development.md:34-85`
- 修改：`docs/ios-progress.md:1-36`
- 修改：`docs/ios-validation.md:1-75`
- 修改：`docs/progress.md`
- 修改：`docs/validation.md`

**接口：**

- 输入：Task 3 的真实命令、退出码、测试数量、文件哈希和 App 包资源检查。
- 输出：fresh clone 操作说明和不夸大的当前验证记录。

- [ ] **Step 1：修正已经失效的开发说明**

在 `docs/ios-development.md` 中把“五段 WAV 都已提交”改为：

- 三段小型 WAV 由 Git 跟踪；
- 两段雨声只跟踪 Ogg 源音频；
- fresh clone 必须先安装 FFmpeg 并运行准备命令；
- 脚本拒绝覆盖，重新生成前只删除两个被忽略输出；
- CI 会自动完成相同准备并检查五个 App 包资源。

文档使用便携命令：

```bash
brew install ffmpeg
python3 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
python3 tools/prepare_ios_audio.py --ffmpeg "$(command -v ffmpeg)"
```

- [ ] **Step 2：在 iOS 进度和验证文档增加 2026-09-24 当前状态**

准确记录：

- Git 历史清理已完成且不再重写；
- 两个大型 WAV 改为生成资源；
- Task 3 实际使用的 Python、FFmpeg、Xcode、模拟器和命令结果；
- XCTest 真实数量；
- App 包五个资源检查；
- 真机各项仍保持“未测”，直到 Task 5 以后取得证据。

保留 2026-09-23 的历史证据，不把当时已经运行的构建描述删除。

- [ ] **Step 3：在根进度和验证文档加入简短跨平台记录**

增加一段说明：Android 继续直接使用两个 Ogg；iOS 从相同 Ogg 生成被忽略的 PCM WAV；仓库不再保存两个 52 MB 派生文件。只写 Task 3 已经取得的本地证据，不提前写 GitHub Actions 或真机通过。

- [ ] **Step 4：检查文档没有保留错误现状或伪造结果**

```bash
rg -n "five WAV resources are committed|五段 WAV 都已提交" docs README.md && exit 1 || true
rg -n "rain-01.wav|rain-04.wav|prepare_ios_audio.py|未测" \
  docs/ios-development.md docs/ios-progress.md docs/ios-validation.md
git diff --check
```

预期：第一条没有匹配；第二条能看到准备流程和仍未完成的真机项目。

- [ ] **Step 5：提交本地证据和说明**

```bash
git add \
  docs/ios-development.md \
  docs/ios-progress.md \
  docs/ios-validation.md \
  docs/progress.md \
  docs/validation.md
git diff --cached --check
git commit -m "docs: record generated iOS audio workflow"
```

---

### Task 5：推送分支并验证 GitHub Actions

**文件：**

- 修改：仅在云端结果出来后更新 `docs/ios-progress.md`、`docs/ios-validation.md`、`docs/progress.md`、`docs/validation.md`

**接口：**

- 输入：Task 1 至 Task 4 的提交。
- 输出：GitHub Actions 实际运行结果、运行链接、产物信息和准确文档。

- [ ] **Step 1：推送普通提交，不执行任何历史重写**

```bash
git status --short --branch
git log --oneline origin/codex/ios-reliability..HEAD
git push origin codex/ios-reliability
```

预期：普通快进推送成功；不使用 `--force`、`--force-with-lease` 或 `filter-repo`。

- [ ] **Step 2：查看本分支最新 iOS 工作流**

打开：

```text
https://github.com/Resker666/minimal-sleep/actions/workflows/ios-build.yml?query=branch%3Acodex%2Fios-reliability
```

等待由本次 `.github/workflows/ios-build.yml` 推送触发的最新运行结束。记录运行 URL、提交 SHA、总耗时和每一步状态。

- [ ] **Step 3：核对云端关键步骤**

必须实际看到以下步骤成功：

- Set up Python 3.12；
- Install FFmpeg；
- Prepare generated iOS audio；
- Run iOS tests；
- Build unsigned simulator app；
- Verify and package simulator app；
- Upload simulator app。

如果失败，保存失败步骤和最后相关日志，使用 `superpowers:systematic-debugging` 查明原因，不通过放宽检查来取得绿色状态。

- [ ] **Step 4：核对 GitHub Artifact**

在运行页面确认存在名称以 `minimal-sleep-ios-simulator-` 开头、末尾为 GitHub 实际运行编号的产物，并记录 GitHub 提供的摘要。若当前登录状态允许下载，解压外层 Artifact ZIP，核对内部 `MinimalSleep-iOS-Simulator.zip` 与 `.sha256` 文件，并验证内部 SHA-256。

不能下载时，只记录 GitHub 页面实际显示的产物名称、大小和摘要，不声称独立解压成功。

- [ ] **Step 5：记录云端证据并提交**

把实际运行链接、结果、时间、产物名称、大小、摘要以及是否完成独立下载核对写入四份进度/验证文档。然后运行：

```bash
git add docs/ios-progress.md docs/ios-validation.md docs/progress.md docs/validation.md
git diff --cached --check
git commit -m "docs: record generated-audio iOS CI run"
git push origin codex/ios-reliability
```

---

### Task 6：完成真机基础、循环和定时验证

**文件：**

- 修改：`docs/ios-validation.md`
- 修改：`docs/ios-progress.md`
- 可能修改：只有复现出真实缺陷时，修改对应 `ios/MinimalSleep/**` 文件并新增或扩展相关 `ios/MinimalSleepTests/**` 测试。

**接口：**

- 输入：Task 3 生成的五个完整资源、当前 Personal Team 和 iPhone `朱颜辞镜花辞树`。
- 输出：基础短测、两次循环边界和真实 15 分钟定时的可核对结果。

- [ ] **Step 1：在隔离 worktree 打开项目并安装到真机**

打开 `ios/MinimalSleep.xcodeproj`，在 `MinimalSleep` target 的 Signing & Capabilities 中选择本机已有 Personal Team，选择 `朱颜辞镜花辞树` 后 Run。

安装前确认：

- 手机已解锁并信任此 Mac；
- Developer Mode 已启用；
- 不卸载已有 App；
- Xcode 打开的路径是隔离 worktree，而不是主工作区。

- [ ] **Step 2：执行基础短测**

依次验证：

1. 冷启动不自动播放；
2. 大雨剪辑、雨雷剪辑、合成大雨、合成海浪、白噪声都能发声；
3. 连续切换时只保留一个声音；
4. 音量滑块生效；
5. App 和锁屏播放、暂停状态一致；
6. 两段授权雨声在锁屏显示 Resker666 / CC BY 4.0；
7. 没有资源缺失错误。

记录手机型号、iOS、Xcode、分支提交和测试时间。

- [ ] **Step 3：测试两个循环边界**

对 `rain-01` 和 `rain-04` 分别连续播放至少 10 分钟，覆盖两个 298 秒边界。每个边界由用户确认：

- 是否出现静音；
- 是否有爆音或点击声；
- 是否有重复瞬态；
- 是否有明显音量变化；
- 播放状态是否保持。

功能上跨过边界但用户没有听到边界时，只能记录“持续播放通过，接缝听感未确认”。

- [ ] **Step 4：测试真实 15 分钟定时**

选择 15 分钟，开始播放后锁屏。在接近结束时观察并听取：

- 倒计时是否按真实时间结束；
- 最后十秒是否淡出；
- 到期后声音和锁屏状态是否停止；
- 到期后按锁屏播放是否会错误恢复过期会话。

- [ ] **Step 5：处理发现的问题**

如果任一步失败：

1. 记录最小复现步骤；
2. 使用 `superpowers:systematic-debugging` 定位原因；
3. 在对应 XCTest 中先复现失败；
4. 实现最小修复；
5. 运行新增测试、完整 XCTest 和 Task 3 的 App 包检查；
6. 使用描述实际缺陷的提交信息单独提交。

没有失败时不创建假想修复或额外重构。

- [ ] **Step 6：移除 Personal Team 的工作区差异并记录结果**

先检查：

```bash
git diff -- ios/MinimalSleep.xcodeproj/project.pbxproj ios/MinimalSleep/Info.plist
```

确认 diff 只包含 Xcode Personal Team 和格式整理后，恢复这两个文件到分支版本：

```bash
git restore ios/MinimalSleep.xcodeproj/project.pbxproj ios/MinimalSleep/Info.plist
```

把真实真机结果写入 iOS 两份文档并提交：

```bash
git add docs/ios-progress.md docs/ios-validation.md
git diff --cached --check
git commit -m "docs: record iOS playback device validation"
git push origin codex/ios-reliability
```

---

### Task 7：验证后台路由、导入、数据保留和飞行模式

**文件：**

- 修改：`docs/ios-validation.md`
- 修改：`docs/ios-progress.md`
- 可能修改：仅在真实缺陷复现后修改对应 iOS 实现和测试。

**接口：**

- 输入：Task 6 已通过的真机基础版本。
- 输出：30 至 60 分钟后台、路由安全、三种导入格式、覆盖安装和离线证据。

- [ ] **Step 1：生成公开可用的导入测试文件**

只使用仓库的 Apache-2.0 白噪声生成 5 秒测试文件：

```bash
mkdir -p /tmp/minimal-sleep-import-fixtures

ffmpeg -y \
  -i ios/MinimalSleep/Resources/white_noise.wav \
  -t 5 -c:a libmp3lame \
  /tmp/minimal-sleep-import-fixtures/white-noise-test.mp3

ffmpeg -y \
  -i ios/MinimalSleep/Resources/white_noise.wav \
  -t 5 -c:a aac \
  /tmp/minimal-sleep-import-fixtures/white-noise-test.m4a

ffmpeg -y \
  -i ios/MinimalSleep/Resources/white_noise.wav \
  -t 5 -c:a pcm_s16le \
  /tmp/minimal-sleep-import-fixtures/white-noise-test.wav
```

通过 Finder、AirDrop 或 iCloud Drive 把这三个测试文件放入手机“文件”App；不使用用户私人音频。

- [ ] **Step 2：执行 30 至 60 分钟锁屏播放**

从 Xcode 停止调试连接但不终止已安装 App，在手机上启动播放并锁屏。记录开始、结束、声音、路由、是否充电和是否发生中断。持续播放只能证明该次条件下通过。

- [ ] **Step 3：验证路由和中断安全**

分别执行：

1. 使用耳机播放后断开耳机；
2. 使用蓝牙设备播放后断开蓝牙；
3. 启动另一个音频 App 抢占音频；
4. 在方便且不产生隐私问题时接听一次测试来电。

预期：极简睡眠暂停，不突然转为扬声器，不未经用户操作自动恢复。每项分别记录，不用其中一项代替另一项。

- [ ] **Step 4：验证导入、取消和删除**

通过系统文件选择器分别导入 Task 7 Step 1 的 MP3、M4A、WAV，并取消一次选择。确认：

- 三种文件都能导入、选择和播放；
- 取消不显示错误；
- 同名或重复导入不会覆盖原文件；
- 删除当前播放项前先停止；
- 删除后其他导入项仍存在。

- [ ] **Step 5：验证重启、覆盖安装和飞行模式**

1. 保留至少一个导入项，强制退出并重新打开；
2. 确认导入项和偏好仍存在，冷启动不自动播放；
3. 从 Xcode 再次 Run 覆盖安装，不卸载 App；
4. 确认私有导入项仍存在；
5. 开启飞行模式，分别播放内置和导入声音。

- [ ] **Step 6：按 Task 6 的调试规则处理失败，并记录证据**

任何失败都先复现、测试、最小修复和完整回归。完成后只提交实际结果：

```bash
git add docs/ios-progress.md docs/ios-validation.md
git diff --cached --check
git commit -m "docs: record iOS background and import validation"
git push origin codex/ios-reliability
```

---

### Task 8：完成整夜播放和阶段收尾

**文件：**

- 修改：`docs/ios-progress.md`
- 修改：`docs/ios-validation.md`
- 修改：`README.md`，仅在平台状态摘要需要更新时修改。

**接口：**

- 输入：Task 6 和 Task 7 已通过的真机版本。
- 输出：一次八小时播放记录、剩余风险和可审阅的最终分支。

- [ ] **Step 1：准备八小时测试条件**

记录：

- 手机型号、iOS 和 App 提交；
- 安装方式；
- 声音和“整晚”模式；
- 输出设备；
- 是否充电、起始电量、低电量模式、屏幕状态和大致温度；
- 开始时间。

启动播放后断开 Xcode 调试器并锁屏。不要在测试期间卸载、重新安装或强制结束 App。

- [ ] **Step 2：八小时后记录结果**

记录结束时间、结束电量、播放是否仍在继续、锁屏状态、路由、设备温度以及任何中断。USB 充电状态下不计算耗电结论。

如果当天无法安排八小时测试，在文档中保留明确的“待执行”条件和步骤，本阶段不得宣称整夜可靠性已经验证。

- [ ] **Step 3：运行最终自动化验证**

重新运行 Task 3 的完整命令：

- Python 音频测试；
- 两个固定 WAV 哈希；
- 完整 XCTest；
- Release 模拟器构建；
- App 包五个声音检查；
- `git ls-files` 与 `git check-ignore`；
- `git diff --check`。

同时运行：

```bash
git status --short --branch
git diff origin/main...HEAD --stat
git diff origin/main...HEAD -- ios .github | \
  rg -n "DEVELOPMENT_TEAM|PRIVATE KEY|mobileprovision" && exit 1 || true
```

预期：没有 Personal Team 或凭据，没有生成 WAV，没有未解释的工作区修改。

- [ ] **Step 4：更新最终状态并提交**

在 iOS 文档中列出：

- 已通过的自动化和真机项目；
- 失败或未测项目；
- 八小时测试条件和结果；
- 仍不能推断的设备范围、耗电和听感结论。

如果 README 的“真机未验收”描述已经不准确，再同步修改。提交：

```bash
git add docs/ios-progress.md docs/ios-validation.md README.md
git diff --cached --check
git commit -m "docs: complete iOS reliability validation"
git push origin codex/ios-reliability
```

- [ ] **Step 5：进入分支收尾流程**

使用 `superpowers:verification-before-completion` 根据最新命令输出确认结果，再使用 `superpowers:finishing-a-development-branch` 向用户提供保留分支、创建 PR 或合入 `main` 的明确选择。未得到用户选择前不自动合并或删除分支。
