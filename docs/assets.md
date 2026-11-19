# iOS 内置音频与来源

本仓库独立包含两段 Ogg 源素材和三段小型 WAV，构建不读取 Android 仓库。

- `assets/source-audio/rain-01.ogg` 和 `rain-04.ogg`：Resker666 本人录制，CC BY 4.0。
  原剪辑各取第 600–900 秒、交叉淡化 2 秒，第二段降低到 0.75 倍增益，得到 298 秒 Ogg。
  原始 MP3 不随仓库分发；迁移复制的 Ogg 字节不变。
- 白噪声、大雨与海浪 WAV：原项目固定种子生成，Apache-2.0；程序合成近似音，非真实天气录音。
- 各文件 SHA-256 与来源见根目录 `assets-manifest.csv`；源代码历史仍保留原生成记录。

两端分别维护这些素材的副本；以后修改不会自动同步。`tools/generate_noise.py` 和
`tools/generate_nature.py` 是可选的素材重建工具，默认输出到 iOS Resources，拒绝覆盖已有
WAV。噪声脚本会重写其 `--manifest` 指定的清单，因此重新设计声音时请将 `--output-dir`
和 `--manifest` 指向单独临时目录，人工审阅后再更新正式资源清单，不要直接覆盖正式清单。
正常构建只运行 `tools/prepare_ios_audio.py`，不重新合成 WAV。

## iOS 资源准备

白噪声、合成大雨、合成海浪本来就是 48 kHz、16-bit、单声道 PCM WAV，因此仅逐字节复制到 `ios/MinimalSleep/Resources/`，没有重新生成、转码或改动 Android 原件。三份 iOS 副本的 SHA-256 分别与 Android 原件相同：

| iOS 资源 | SHA-256 |
|---|---|
| `white_noise.wav` | `bbc0563b65641da92ef3143def417bb7aa22f3d3d383e1235af3496c7681e3e0` |
| `heavy_rain.wav` | `13104bdce5e7f7f4cfcada32f34a205f321d1247f53fe80be737c04aa06675fa` |
| `ocean_waves.wav` | `b238fb1803bf8356572c5b7b055a38f84f8ffbcc5c78f147c00c73b7b020ffaa` |

两段雨声不能把 Ogg 直接声明为 AVAudioPlayer 可播放资源。`tools/prepare_ios_audio.py` 读取已经完成循环剪辑的 `assets/source-audio/rain-01.ogg`、`rain-04.ogg`，使用 FFmpeg 输出 128 kbps AAC/M4A；命令没有再次裁剪、交叉淡化、滤镜、增益、声道转换或重采样。脚本拒绝覆盖输出，要求每个文件不超过 6,500,000 字节，并在成功后写入源/输出 SHA-256、完整命令、编码参数、作者 **Resker666**、许可证 **CC BY 4.0** 和修改说明到 `ios/MinimalSleep/Resources/audio-derivations.json`，同时更新 `assets-manifest.csv`。

2026-09-24 在 M4 Mac 上使用 Homebrew FFmpeg 9.0.2 实际生成两段派生资源。两份输出均为 298 秒、44.1 kHz、双声道 AAC/M4A：

| iOS 录制雨声派生资源 | 字节 | SHA-256 |
|---|---:|---|
| `rain-01.m4a` | 4,834,016 | `ea9a392d6e262d19db2c9ef8c1bb31ce81db2ecc420d11fd474217e7d15594fc` |
| `rain-04.m4a` | 4,859,928 | `b779392b3ff4c7a24d2459477c4d8e28969cb123e1989c507942266e385ca85b` |

若需要从头重新派生，先有意移除已有输出，再从仓库根目录运行：

```bash
/opt/homebrew/bin/python3.12 tools/prepare_ios_audio.py \
  --ffmpeg /opt/homebrew/bin/ffmpeg \
  --ffprobe /opt/homebrew/bin/ffprobe
```

这一步只派生 iOS 文件，不覆盖两份源 Ogg。脚本拒绝覆盖已有输出。雨声保留 Resker666 / CC BY 4.0 署名；AAC 是有损压缩，仍须在 iPhone 上跨实际循环边界试听，格式、时长和哈希检查不能证明接缝听不出。
