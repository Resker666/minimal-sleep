# 内置声音来源与生成

当前 APK 有三段本仓库固定种子生成的声音，以及两段 Resker666 录制雨声的剪辑。三段合成音由 `tools/generate_noise.py` 与 `tools/generate_nature.py` 生成，均为 48 kHz、16-bit、单声道 PCM WAV，按 Apache-2.0 提供。两段录制雨声为 Ogg Vorbis，按 CC BY 4.0 提供。每段路径、作者、来源和 SHA-256 见 `assets-manifest.csv`。

- 白噪声：每个采样独立取伪随机值。种子固定以便重建，声学统计没有经过设备扬声器校准。
- 大雨：24 秒。宽频雨幕、带通雨丝与随机短促雨滴叠加，是程序合成的雨声近似，不是真实雨天录音。
- 海浪：40 秒。低频水声、中频拍岸声与浪尖泡沫噪声，使用 8 秒和 10 秒周期的缓慢起伏。是程序合成的海浪近似，不是真实海岸录音。

`tools/generate_noise.py` 仍保留粉红、棕噪声的历史生成方法，但当前 APK 不再打包对应 WAV，也不提供选择项。

## 录制雨声剪辑

用户于 2026-09-22 确认 `rain-01.ogg` 与 `rain-04.ogg` 的原始音轨均由本人录制，授权以 **Resker666** 署名按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 随公开源码与 APK 分发、修改。此来源声明来自录制者本人；文件名中的 B 站视频编号未用于推断第三方许可。原始 MP3 仍保留在本地 `source/`，不纳入 Git。两段内置 Ogg 从各自原音第 600 秒取 300 秒，尾首交叉淡化 2 秒，最终 298 秒；`rain-04.ogg` 另用 `--gain 0.75` 降低增益。变更由 `tools/prepare_loop.py` 完成，原始/输出 SHA-256 与具体参数见 `deliverables/audio-previews-v4/manifest.json` 的本地处理记录；公开输出哈希也在 `assets-manifest.csv`。接缝听感仍需实际试听。

| 内置剪辑 | 本地原始 MP3 SHA-256 | 处理后 SHA-256 |
|---|---|---|
| `rain-01.ogg` | `964AD60FD4137459FFC0E877EAE538C4DCC438864770C4A7152C867F59E0EEE0` | `B1CACE1E59C4248E0E21686543E100AA611A9F8F3875C47757D67FDDD90C9CC9` |
| `rain-04.ogg` | `2F57FD290B6458B7D0C4ECB5279A16B145D21AB8BAD97C58DBA8ADF17A482AE0` | `888FC1071E05DEE973487B93A35B6CBECFBFE61FD0342E53F115A945EDE9A61E` |

## 合成音的生成细节

三段合成音生成后减去均值，将结尾一小段与开头反向片段做线性交叉淡化，保留峰值余量。脚本测试验证输出确定性、有限值、无数字削波、首尾采样值连续、海浪起伏与 WAV 格式。实际听感和循环接缝仍需真机主观确认，尤其是蓝牙设备。

重建：在仓库根目录分别执行 `python tools/generate_noise.py` 和 `python tools/generate_nature.py`。默认写入 `app/src/main/res/raw/`；噪声脚本创建清单，自然声脚本打印 SHA-256，需手动更新清单。现有文件存在时会退出，以防误覆盖。

## iOS 资源准备

2026-09-22 的 Windows 准备轮次没有 Mac、Xcode 或 Swift。白噪声、合成大雨、合成海浪本来就是 48 kHz、16-bit、单声道 PCM WAV，因此仅逐字节复制到 `ios/MinimalSleep/Resources/`，没有重新生成、转码或改动 Android 原件。三份 iOS 副本的 SHA-256 分别与 Android 原件相同：

| iOS 资源 | SHA-256 |
|---|---|
| `white_noise.wav` | `bbc0563b65641da92ef3143def417bb7aa22f3d3d383e1235af3496c7681e3e0` |
| `heavy_rain.wav` | `13104bdce5e7f7f4cfcada32f34a205f321d1247f53fe80be737c04aa06675fa` |
| `ocean_waves.wav` | `b238fb1803bf8356572c5b7b055a38f84f8ffbcc5c78f147c00c73b7b020ffaa` |

两段雨声不能把 Ogg 直接声明为 AVAudioPlayer 可播放资源。新增的 `tools/prepare_ios_audio.py` 读取已经完成循环剪辑的 `app/src/main/assets/local-sounds/rain-01.ogg`、`rain-04.ogg`，使用 FFmpeg `pcm_s16le` 输出 PCM WAV；命令没有裁剪、交叉淡化、滤镜、增益、声道转换或重采样。脚本拒绝覆盖输出，并在成功后写入源/输出 SHA-256、完整命令、PCM 参数、作者 **Resker666**、许可证 **CC BY 4.0** 和修改说明到 `ios/MinimalSleep/Resources/audio-derivations.json`，同时更新 `assets-manifest.csv`。

本机 PATH 与仓库 `.tools` 均未找到 FFmpeg 或其他 Ogg 解码器，因此本轮**没有实际生成** `rain-01.wav`、`rain-04.wav`，也没有输出哈希；不得把脚本存在解释为转码完成。今晚在 M4 上安装/确认 FFmpeg 后，从仓库根目录运行：

```bash
python3 tools/prepare_ios_audio.py
```

这一步只派生 iOS 文件，不覆盖两份 Android Ogg。脚本成功生成的雨声仍须保留 Resker666 / CC BY 4.0 署名，并在 iPhone 上跨实际循环边界试听；PCM 格式和哈希检查不能证明接缝听不出。
