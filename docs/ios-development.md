# iOS development handoff

## Current environment

This preparation was performed on a company Windows computer on 2026-09-22. There is no Mac, Xcode, iOS simulator, or connected iPhone in this environment. Per the task boundary, none of `sw_vers`, `xcode-select`, `xcodebuild`, `simctl`, or `devicectl` was run. Task 0 environment verification remains for the M4 Mac tonight.

The repository baseline was clean `main` at `2e22a7405551ec5f9540657d06388a44f098aba4`; work continued on `codex/ios-mvp`. No Apple build result exists yet.

## Create the Xcode project tonight

1. Run every task 0 command from `docs/minimal-sleep-ios-codex-plan.md` on the M4 and paste versions, destinations, exit codes, and any device visibility issue into this file and `docs/ios-validation.md`.
2. Run `python3 tools/prepare_ios_audio.py` with an installed `ffmpeg`. Confirm the command prints hashes for both rain WAV files and that `audio-derivations.json` and `assets-manifest.csv` contain the same hashes.
3. Create a temporary Xcode iOS App project named `MinimalSleep`: SwiftUI interface, Swift language, XCTest included, and no new Git repository. Move the resulting `MinimalSleep.xcodeproj` to `ios/`, then replace its generated source references with the existing `ios/MinimalSleep/` tree. Add `ios/MinimalSleepTests/` only to the test target.
4. In the app target, set Bundle Identifier `io.github.resker666.minimalsleep` and iOS deployment target 17.0. Add all five resource WAV files to the app target and **Copy Bundle Resources**.
5. Add only the background `audio` mode. Do not add `NSMicrophoneUsageDescription`; this playback MVP must not request microphone permission. Do not enable HealthKit, Watch, alarm, account, network, or recording features.
6. Replace the explicit `TODO（需 Mac 编译）` boundaries with real AVFoundation/MediaPlayer implementations, keeping one player/session owner and the existing state-machine rules. Run XCTest and simulator builds before signing work.

## Personal Team device installation

1. In Xcode **Settings > Accounts**, sign in to the user's Apple ID. Never put the account password, certificate, profile, or team identifier in documentation or Git.
2. In the `MinimalSleep` target's **Signing & Capabilities**, enable automatic signing and select the user's real Personal Team. If the exact Bundle ID conflicts, record the error before choosing any alternative; do not invent a team or identifier.
3. Connect the iPhone, unlock it, trust the Mac if prompted, and enable Developer Mode only through the device's normal system prompt/settings.
4. Select that iPhone as the run destination and press Run. A free Personal Team build is a development install and may require periodic re-signing; it is not an App Store or permanent distribution build.
5. Do not uninstall an app merely to resolve signing if it contains user data. Record the installed commit, iOS/Xcode versions, and result in `docs/ios-validation.md`.

## Source boundaries prepared on Windows

- `SleepTimerPolicy` uses an injected monotonic uptime and absolute deadline. UI ticks only refresh derived state.
- `ImportedSoundStore` is an actor, uses UUID filenames, enforces all four limits after staged copy, commits the index last, and stops current playback before deletion.
- `AudioCoordinator` and `NowPlayingController` define state and call points only. They do not claim AVFoundation or MediaPlayer playback.
- The first build must remain offline and playback-only. Recording, microphone permission, LiteRT/YAMNet, HealthKit, Watch, alarms, accounts, and networking remain outside this pass.
