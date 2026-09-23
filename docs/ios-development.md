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

## Audio resource regeneration

The five WAV resources are committed, so normal app builds do not need Python or FFmpeg. To regenerate the two licensed rain derivatives from the existing Android Ogg files:

```bash
/opt/homebrew/bin/python3.12 tools/prepare_ios_audio.py \
  --ffmpeg /opt/homebrew/bin/ffmpeg
```

The script refuses to overwrite existing output. Remove generated derivatives only when intentionally regenerating them, then verify the resulting hashes against `ios/MinimalSleep/Resources/audio-derivations.json` and `assets-manifest.csv`.

Homebrew's regular FFmpeg 9.0.2 can decode Vorbis and write PCM, but it does not include the `libvorbis` encoder. The iOS preparation tests pass and iOS resource generation succeeds. Four older `prepare_loop` tests that create Ogg output fail in this local environment with `Unknown encoder 'libvorbis'`; this is a tool capability difference, not an iOS source failure.

## Personal Team installation

1. Open Xcode **Settings > Accounts** and sign in with your Apple ID. Do not place the password, certificate, provisioning profile, or Team ID in the repository.
2. Select the `MinimalSleep` target, open **Signing & Capabilities**, enable automatic signing, and choose your real Personal Team.
3. Connect and unlock the iPhone. Trust the Mac and enable Developer Mode only through the phone's normal prompts and settings.
4. Select the iPhone as the run destination and press Run.
5. If the exact bundle identifier conflicts, record the Xcode error before changing it. Do not uninstall an existing app that contains private imported data merely to solve signing.

The current physical iPhone is visible to CoreDevice but unavailable, so signing, installation, background playback, lock-screen behavior, route changes, and listening tests still require user action on the device.
