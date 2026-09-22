# 本地自然声循环剪辑

`source/` 中的 MP3 是用户提供的本地试听素材，当前没有可核验的再分发许可。它们被 `.gitignore` 排除，**不得直接加入 Git、公开 APK 或 Release**。文件名中的视频编号和“真实”字样均不能代替原作者、原始链接和许可证明。原始文件始终保留不改。

## 剪辑方法

长音频先试听并选取声音稳定、没有人声/音乐/片头片尾的连续区间，再用 `tools/prepare_loop.py` 把片尾与片头交叉淡化。需要本机安装 FFmpeg 和 FFprobe。示例：

```powershell
python tools/prepare_loop.py --input 'source/待处理.mp3' --output 'deliverables/audio-previews/example.ogg' --start 600 --duration 300 --crossfade 2
```

这会选取从第 10 分钟开始的 5 分钟，输出约 298 秒的 Ogg Vorbis 循环。`--gain` 可以将过响素材整体降低，例如 `--gain 0.75`。脚本拒绝覆盖已存在的输出；剪辑和编解码参数必须随每段素材单独记录。Ogg Vorbis 在 Android 支持的音频格式内，但电脑上的波形、解码和峰值检查不能代替目标手机试听。

短音频先保持完整长度。仍须检查结尾接回开头时的静音、音量变化、突兀声音和实际设备上的解码接缝；发现问题时只修接缝，不必为缩小体积强行裁短。播放器目前使用 Media3 的 `REPEAT_MODE_ONE`，循环是否无感取决于素材和设备表现。

## 本轮本地预览

本机最终候选位于被 Git 忽略的 `deliverables/audio-previews-v4/`；`manifest.json` 记录五段长音频的原文件路径、原文件和输出 SHA-256、起点、长度、交叉淡化及增益。五段均从原文件第 10 分钟取 5 分钟，最终各 298 秒，约 4.1–4.4 MB。两段短 MP3 仅复制用于试听，没有裁剪。早期 `audio-previews/`、`audio-previews-v2/` 和 `audio-previews-v3/` 是实验中间结果，不作为候选。

2026-09-21 已将 v4 七段试听文件复制到手机 `Download/minimal-sleep-loop-previews-v4/`，电脑与手机 SHA-256 一致。`rain-01.ogg` 已在现有 App 中导入和短时播放成功，测试副本随后已从 App 中删除。可从 App 的“导入本地音频”逐段选择并试听。**尚未完成连续循环听感或整夜试播验收。**

## 仅本机调试包（2026-09-22）

用户已允许裁剪并要求内置试听，但原作者再分发授权仍待提供。为便于这台手机试听，把 `rain-01.ogg`（大雨）和 `rain-04.ogg`（雨雷）复制到被 Git 忽略的 `app/src/debug/assets/local-sounds/`，原件和 v4 候选均未改动。应用仅在发现这些可选文件时显示“本机素材试听”选项；正常源码仓库没有该目录，release 构建也不含这两段音频。它们使用现有 Media3 播放器的循环和定时逻辑，录音时仍按播放区间标记干扰，不声称消除回声。

私有调试 APK 为 `deliverables/minimal-sleep-v0.3.1-local-rain-debug.apk`。它只供本机安装和听感验证，**不得上传 GitHub、发送给他人或作为公开 Release 发布**。`rain-01.ogg` 已在真机播放跨过一次 298 秒边界，媒体会话维持 `PLAYING` 并从约 279 秒回到约 17 秒；这只能证明功能性循环。`rain-04.ogg` 的完整循环、两段的接缝听感、主观响度和整夜播放仍需试听。若要正式内置，先满足下方许可门槛，再按实际授权范围决定能否把素材放进仓库与公开 APK。

## 内置前的门槛

为每段拟内置音频保存原作者、原始链接、明确允许修改并随 APK 分发的许可或书面授权、署名要求和文件哈希。确认后只挑选少量听感不同的片段放入 App，更新 `assets-manifest.csv`、`THIRD_PARTY_NOTICES.md` 和 UI 名称，再构建并在手机上重复试听。当前仓库的 Apache-2.0 源码许可证不自动覆盖这些外来录音。没有授权证明时，保持用户自己在手机上本地导入的方式。
