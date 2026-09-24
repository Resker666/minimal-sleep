# iOS development

## Verified local environment

Checked on 2026-09-23:

| Item | Actual value |
|---|---|
| Mac | Apple silicon (`arm64`) |
| macOS | 27.0 (`26A428`) |
| Active developer directory | `/Applications/Xcode.app/Contents/Developer` |
| Xcode | 27.0 (`27A266a`) |
| iOS SDK | 27.0 |
| iOS Simulator SDK/runtime | 27.0 |
| Test simulator | iPhone 18 Pro, iOS 27.0, `75FA9690-7229-4F85-96C1-284AD9262383` |
| Physical device visibility | `朱颜辞镜花辞树`, iPhone18,1, listed as `unavailable` |
| Python used for audio tools | Homebrew Python 3.12.14 |
| FFmpeg used for iOS derivation | Homebrew FFmpeg 9.0.2 |

The work started from `codex/ios-mvp` at `4d8abbb`. Local `main` was merged without conflicts, producing `b37aba5`, before the Mac implementation continued.

## Project configuration

- Project: `ios/MinimalSleep.xcodeproj`
- Shared scheme: `MinimalSleep`
- Deployment target: iOS 17.0
- Bundle identifier: `io.github.resker666.minimalsleep`
- Background mode: `audio`
- App entry: `ios/MinimalSleep/App/MinimalSleepApp.swift`
- Tests: `ios/MinimalSleepTests/`

The playback MVP does not declare `NSMicrophoneUsageDescription` and does not contain recording, HealthKit, Watch, account, network, or model-inference features. Imported files and their JSON index live in the app's private Application Support directory and are excluded from backup.

## Build from Terminal

```bash
xcodebuild -list -project ios/MinimalSleep.xcodeproj

xcodebuild -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/minimal-sleep-ios-derived \
  build CODE_SIGNING_ALLOWED=NO

xcodebuild -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=75FA9690-7229-4F85-96C1-284AD9262383' \
  -derivedDataPath /tmp/minimal-sleep-ios-tests \
  test

xcodebuild -project ios/MinimalSleep.xcodeproj \
  -scheme MinimalSleep \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/minimal-sleep-ios-device-derived \
  build CODE_SIGNING_ALLOWED=NO
```

The test destination UUID is local evidence, not a portable command. On another Mac, use `xcrun simctl list devices available` and substitute an available iPhone simulator.

## Audio preparation after a fresh clone

Git tracks these three smaller iOS WAV resources directly:

- `ios/MinimalSleep/Resources/heavy_rain.wav`
- `ios/MinimalSleep/Resources/ocean_waves.wav`
- `ios/MinimalSleep/Resources/white_noise.wav`

The two 298-second rain AAC/M4A files are generated build inputs. Git tracks their shared Android/iOS Ogg sources at `app/src/main/assets/local-sounds/rain-01.ogg` and `rain-04.ogg`, while `.gitignore` excludes the generated `rain-01.m4a`, `rain-04.m4a`, temporary `.rain-*.transcoding.m4a` files, and obsolete generated WAV names.

After a fresh clone, prepare the full iOS resources before running Xcode locally:

```bash
brew install ffmpeg
python3 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
python3 tools/prepare_ios_audio.py --ffmpeg "$(command -v ffmpeg)"
```

The script refuses to overwrite an existing output. To intentionally regenerate, delete only `ios/MinimalSleep/Resources/rain-01.m4a` and `rain-04.m4a`, rerun the commands, and verify that `assets-manifest.csv` and `ios/MinimalSleep/Resources/audio-derivations.json` have no unexpected diff. Remove obsolete `rain-01.wav` and `rain-04.wav` files if an older workspace still has them. Do not add generated audio files to Git.

GitHub Actions performs the same preparation automatically, checks that the generated files remain untracked, and refuses to upload the simulator App unless the two M4A rain resources and three WAV resources are present and the obsolete rain WAV files are absent. Local revalidation on 2026-09-24 used Homebrew Python 3.12 and FFmpeg 9.0.2.

## Personal Team installation

1. Open Xcode **Settings > Accounts** and sign in with your Apple ID. Do not place the password, certificate, provisioning profile, or Team ID in the repository.
2. Select the `MinimalSleep` target, open **Signing & Capabilities**, enable automatic signing, and choose your real Personal Team.
3. Connect and unlock the iPhone. Trust the Mac and enable Developer Mode only through the phone's normal prompts and settings.
4. Select the iPhone as the run destination and press Run.
5. If the exact bundle identifier conflicts, record the Xcode error before changing it. Do not uninstall an existing app that contains private imported data merely to solve signing.

The current physical iPhone is visible to CoreDevice but unavailable, so signing, installation, background playback, lock-screen behavior, route changes, and listening tests still require user action on the device.
