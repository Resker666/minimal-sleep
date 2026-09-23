# iOS app

Open `MinimalSleep.xcodeproj` with Xcode. The shared scheme is `MinimalSleep`, the deployment target is iOS 17.0, and the bundle identifier is `io.github.resker666.minimalsleep`.

The playback MVP is wired end to end:

- one `AVAudioPlayer` and `.playback` audio session;
- five bundled offline sounds, including two Resker666 / CC BY 4.0 rain recordings;
- 15/30/60/90 minute or all-night sessions with a final 10-second fade;
- background audio, lock-screen metadata, and play/pause commands;
- interruption and headphone-removal pause without automatic resume;
- private MP3/M4A/WAV import, decode validation, limits, persistence, playback, and deletion;
- persisted duration and volume, without cold-launch autoplay.

## Build and test

```bash
xcodebuild -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/minimal-sleep-ios-derived build CODE_SIGNING_ALLOWED=NO

xcodebuild -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/minimal-sleep-ios-tests test

xcodebuild -project ios/MinimalSleep.xcodeproj -scheme MinimalSleep -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/minimal-sleep-ios-device-derived build CODE_SIGNING_ALLOWED=NO
```

The committed WAV files are sufficient to build. Python 3.12 and FFmpeg are required only when regenerating the two iOS rain derivatives with `tools/prepare_ios_audio.py`.

## Install on an iPhone

1. Open Xcode **Settings > Accounts** and sign in with your Apple ID.
2. Select the `MinimalSleep` target, open **Signing & Capabilities**, enable automatic signing, and choose your real Personal Team.
3. Connect and unlock the iPhone, trust the Mac if prompted, and enable Developer Mode from the phone's normal settings prompt.
4. Select the iPhone as the run destination and press Run.

Do not add credentials or a Development Team value to Git. An unsigned device build verifies arm64 compilation but cannot be installed. Physical-device acceptance work remains in `docs/ios-validation.md`.
