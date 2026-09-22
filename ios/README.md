# iOS source handoff

This directory currently contains Swift sources, XCTest files, and prepared resources only. It intentionally has no `.xcodeproj` or `.xcworkspace`; the Windows preparation pass did not run or claim an Apple build.

## Continue on the M4 Mac

1. Start with task 0 in `docs/minimal-sleep-ios-codex-plan.md`. Record the actual macOS, Xcode, SDK, simulator, and connected-device results in `docs/ios-development.md`. Do not repeat the Windows source preparation.
2. Confirm `ffmpeg` is available, then run `python3 tools/prepare_ios_audio.py`. It reads the two existing Android Ogg files and creates `rain-01.wav`, `rain-04.wav`, and `audio-derivations.json` in `ios/MinimalSleep/Resources/`; it does not overwrite the Ogg files or redo their loop edit.
3. In Xcode, create a temporary **iOS App** project named `MinimalSleep` with SwiftUI, Swift, and XCTest. Do not let Xcode create a Git repository. Move only `MinimalSleep.xcodeproj` to `ios/`, open it, remove its generated source references, and add the existing `ios/MinimalSleep/` and `ios/MinimalSleepTests/` files with the correct target membership.
4. Set the exact Bundle Identifier to `io.github.resker666.minimalsleep` and the deployment target to iOS 17. Add the five WAV files from `ios/MinimalSleep/Resources/` to **Copy Bundle Resources**.
5. Under **Signing & Capabilities**, select the user's real Personal Team locally. Add only **Background Modes > Audio, AirPlay, and Picture in Picture**. Do not add a microphone usage description, recording capability, HealthKit, networking entitlement, or a fabricated Development Team.
6. Implement the locations marked `TODO（需 Mac 编译）`: one AVFoundation playback engine, MediaPlayer remote commands/metadata, audio validation, the background-safe deadline scheduler, and UI wiring for the imported-sound actor. Do not treat the current protocol-only adapters as working playback.
7. Add the Swift files to the app/test targets and run the `SleepTimerPolicy`, `ImportedSoundStore`, `SoundCatalog`, and `AudioCoordinator` XCTest suites before simulator/device work. Record exact commands and exit codes in `docs/ios-validation.md`.

The playback session category must be `.playback`. Pausing must not extend a deadline; stopping clears it; changing duration restarts it at the operation time; an expired session must reject a later remote play command. The first iOS target must not request microphone access.
