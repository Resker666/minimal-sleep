# iOS validation

Updated: 2026-09-22. This file is intentionally separate from the Android validation record. The preparation environment was Windows without Swift, Xcode, simulator, or iPhone access, so every Apple build and runtime row is **未测**.

| Test | Device / OS / Xcode | Build commit | Conditions | Actual result / evidence | Status |
|---|---|---|---|---|---|
| Swift source compile | 未记录 | 未提交 | Xcode app target | 未运行；当前没有 `.xcodeproj` | 未测 |
| XCTest: timer policy | 未记录 | 未提交 | `SleepTimerPolicyTests` | 测试源码已写，本机无 Swift/Xcode，未运行 | 未测 |
| XCTest: import limits and transactions | 未记录 | 未提交 | `ImportedSoundStoreTests` with fake file system/disk | 测试源码已写，本机无 Swift/Xcode，未运行 | 未测 |
| XCTest: catalog and coordinator expiry | 未记录 | 未提交 | `SoundCatalogTests`, `AudioCoordinatorTests` | 测试源码已写，本机无 Swift/Xcode，未运行 | 未测 |
| Simulator build and launch | 未记录 | 未提交 | iOS 17+ simulator | 未运行 | 未测 |
| Generic iOS device unsigned build | 未记录 | 未提交 | `CODE_SIGNING_ALLOWED=NO` | 未运行 | 未测 |
| Launch, switch, pause, volume | 未记录 | 未提交 | iPhone short test | 未运行 | 未测 |
| Each rain track crosses two loop boundaries | 未记录 | 未提交 | User listening, identify output route | 未运行；功能循环与无缝听感均未验证 | 未测 |
| Locked playback for 30-60 minutes | 未记录 | 未提交 | Screen locked, no debugger keepalive | 未运行 | 未测 |
| Actual 15-minute deadline and final 10-second fade | 未记录 | 未提交 | Screen locked | 未运行 | 未测 |
| Headphone removal, call, and audio interruption | 未记录 | 未提交 | Manual route/interruption tests | 未运行 | 未测 |
| Local/provider MP3, M4A, WAV import and cancel | 未记录 | 未提交 | Legal user-selected fixtures | 未运行 | 未测 |
| Delete current item and rapid switching | 未记录 | 未提交 | Device stress sequence | 未运行 | 未测 |
| Force quit, relaunch, and overwrite install | 未记录 | 未提交 | Preserve imported data; do not uninstall | 未运行 | 未测 |
| Airplane mode | 未记录 | 未提交 | Built-in and imported playback | 未运行 | 未测 |
| Eight-hour overnight playback | 未记录 | 未提交 | Record battery, charging, low-power mode, screen, route, duration, temperature | 未运行 | 未测 |

## Windows-only evidence

- `git status --short --branch`, `git branch --show-current`, and `git rev-parse HEAD` were run before changes; the starting tree was clean `main` at `2e22a7405551ec5f9540657d06388a44f098aba4`.
- Source Ogg and existing PCM WAV SHA-256 values were checked locally against `assets-manifest.csv`.
- No `ffmpeg`, `ffprobe`, or Swift executable was found in PATH or repository `.tools`; rain conversion and every XCTest remain unrun.
- `python.exe -m py_compile tools/prepare_ios_audio.py` and `python.exe tools/prepare_ios_audio.py --help` exited 0. Running the conversion command itself exited 1 with the explicit missing-FFmpeg message and created no rain WAV.
- `python.exe -m unittest discover -s tools -p 'test_*.py' -v` exited 0: 14 tests completed, with 6 pre-existing FFmpeg-dependent loop tests skipped; all 4 new iOS conversion-script tests passed.
- Python `wave` inspection exited 0 and confirmed each copied iOS WAV is 48 kHz, mono, 16-bit, uncompressed PCM. `git diff --check` exited 0.
- These checks are file/source evidence only and do not validate iOS playback, loop quality, background behavior, import decoding, signing, or installation.
