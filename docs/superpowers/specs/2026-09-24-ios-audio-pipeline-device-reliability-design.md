# iOS Audio Pipeline and Device Reliability Design

**Date:** 2026-09-24

**Status:** Approved in conversation; awaiting repository document review

## Goal

Make the existing iOS sleep player reproducible from a fresh clone and validate its current playback feature set on a physical iPhone. The repository must keep the smaller licensed Ogg sources and generate the two large PCM WAV derivatives during preparation and CI without tracking those generated files in Git.

## Scope

This phase includes:

- deterministic preparation of `rain-01.wav` and `rain-04.wav` from the tracked Ogg sources;
- Git ignore and CI checks that prevent those generated WAV files from being committed;
- an iOS CI build whose application bundle contains all five built-in sounds;
- automated regression tests relevant to audio preparation and existing playback behavior;
- staged physical-device validation for playback, looping, lock-screen behavior, timers, route changes, imports, persistence, offline use, and overnight reliability;
- fixes for defects found while performing those validations;
- accurate updates to iOS development, progress, and validation documentation.

This phase excludes microphone recording, sound classification, medical or sleep-quality claims, App Store/TestFlight distribution, signing credentials in CI, and any further Git history rewrite.

## Current State

The iOS client already has a SwiftUI interface, five catalog entries, `AVAudioPlayer` looping, a monotonic sleep timer with a ten-second fade, background audio, lock-screen controls, private MP3/M4A/WAV import, persistence, and deletion. The repository has 31 XCTest cases and a simulator CI workflow.

The Git history cleanup intentionally removed these generated files:

- `ios/MinimalSleep/Resources/rain-01.wav`
- `ios/MinimalSleep/Resources/rain-04.wav`

The tracked source assets remain:

- `app/src/main/assets/local-sounds/rain-01.ogg`
- `app/src/main/assets/local-sounds/rain-04.ogg`

`tools/prepare_ios_audio.py` can decode those Ogg files to 44.1 kHz stereo 16-bit PCM WAV and record derivation metadata. The current CI workflow does not run that preparation step. A fresh-clone CI build can therefore succeed while packaging only three of the five catalog sounds; selecting either recorded-rain entry then fails at runtime with a missing resource.

The existing `.gitignore` re-ignores the two final WAV paths after allowing other iOS WAV resources, but it contains trailing spaces and does not re-ignore the script's `.rain-*.transcoding.wav` temporary files after that allow rule.

The main checkout also has local Xcode project changes produced by Personal Team selection and Xcode normalization. Those machine-specific changes are outside this phase and must not be committed.

## Design Decisions

### 1. Explicit preparation and CI generation

Generated rain WAV files remain outside Git. Developers run one documented preparation command after a fresh clone and before opening or building the complete app:

```bash
python3 tools/prepare_ios_audio.py --ffmpeg ffmpeg
```

The CI workflow runs the same script from a clean checkout before XCTest and the Release simulator build. Audio generation will not be added as an Xcode Run Script build phase. This keeps Xcode builds independent from Homebrew path conventions, avoids running an external transcoder on every incremental build, and makes preparation failures visible as a separate CI step.

The script's existing default behavior remains conservative: it refuses to overwrite an existing output. Regeneration requires intentionally removing the ignored derivatives first. The script continues to create outputs through temporary files and publishes only complete files.

### 2. Source and derivation integrity

The tracked Ogg files are the canonical cross-platform distribution assets for these two recordings. The iOS WAV files are derived build inputs.

CI will:

1. run the focused Python tests for `prepare_ios_audio.py`;
2. record the FFmpeg version used;
3. generate both WAV files from a clean checkout;
4. require both outputs to be non-empty PCM WAV files;
5. require the tracked derivation manifests to remain unchanged after generation;
6. fail if either generated WAV path is present in `git ls-files`.

A manifest difference means the source, decoder output, or documented derivation no longer matches the committed provenance and must be reviewed explicitly.

### 3. Git ignore rules

The exact generated paths will use root-anchored rules placed after the existing iOS WAV exception:

```gitignore
# Generated iOS audio. Rebuild with tools/prepare_ios_audio.py.
/ios/MinimalSleep/Resources/rain-01.wav
/ios/MinimalSleep/Resources/rain-04.wav
/ios/MinimalSleep/Resources/.rain-*.transcoding.wav
```

Other small, intentionally tracked iOS WAV resources remain allowed. No size-based history filter or broad `Resources/*.wav` exclusion will be introduced.

### 4. CI triggers and bundle verification

The iOS workflow will also run when these inputs change:

- `app/src/main/assets/local-sounds/rain-01.ogg`
- `app/src/main/assets/local-sounds/rain-04.ogg`
- `tools/prepare_ios_audio.py`
- `tools/test_prepare_ios_audio.py`
- `assets-manifest.csv`

After building, CI will inspect `MinimalSleep.app` and require these bundled resources:

- `rain-01.wav`
- `rain-04.wav`
- `heavy_rain.wav`
- `ocean_waves.wav`
- `white_noise.wav`

The artifact is uploaded only after this check succeeds. The artifact remains an unsigned simulator application and is not represented as installable on an iPhone.

### 5. Local signing isolation

Personal Team IDs, certificates, provisioning profiles, Apple account data, and Xcode user data remain local. CI continues to use `CODE_SIGNING_ALLOWED=NO` for simulator tests and builds.

Physical-device commands may use the signing state already stored by Xcode on this Mac, but no signing identifiers created by Xcode normalization are included in feature commits. Before each commit, the staged diff must be checked for `DEVELOPMENT_TEAM`, certificate material, profiles, and unrelated project-file normalization.

## Physical-Device Validation

Validation proceeds in increasing duration so short failures are found before overnight testing.

### Stage 1: Smoke test

- install or update the app without uninstalling the existing copy;
- launch without automatic playback;
- play, pause, change volume, and switch through all five built-in sounds;
- confirm lock-screen title, attribution, play, and pause state;
- confirm only one sound plays at a time and no missing-resource error appears.

### Stage 2: Loop boundaries and timer

- play `rain-01` across at least two 298-second boundaries;
- play `rain-04` across at least two 298-second boundaries;
- listen for silence, clicks, duplicated transients, or obvious level changes at each boundary;
- run an actual 15-minute locked-screen timer;
- confirm audible fade during the final ten seconds and stopped state at expiry;
- confirm an expired remote play command does not unexpectedly resume the session.

### Stage 3: Background and route safety

- play with the screen locked for 30 to 60 minutes without debugger keepalive;
- disconnect wired or Bluetooth audio and confirm playback pauses rather than moving unexpectedly to the speaker;
- trigger an audio interruption or competing playback source and confirm the app pauses and does not automatically resume;
- record the output route and the exact action used for each result.

### Stage 4: Import and persistence

- import one legal MP3, one M4A, and one WAV through the system file picker;
- cancel one file-picker operation and confirm it is not shown as an error;
- play and delete an imported sound, including deleting the currently selected item;
- force quit and relaunch, confirming preferences and remaining imports persist without autoplay;
- update the installed app without uninstalling it and confirm private imports remain;
- repeat built-in and imported playback in airplane mode.

No private recording or user-selected audio is copied into the repository, CI, or test logs.

### Stage 5: Overnight playback

After Stages 1 through 4 pass, run one eight-hour playback session without a debugger attached. Record:

- device model and iOS version;
- app commit and installation method;
- selected sound and timer mode;
- start and end time;
- charging state, start/end battery, Low Power Mode, screen state, route, and approximate temperature;
- any playback interruption, unexpected stop, route change, or UI discrepancy.

A test performed while USB charging does not establish battery consumption. Passing one night is evidence for that setup, not a universal reliability claim.

## Error Handling

- Audio preparation stops on a missing source, unavailable FFmpeg binary, stale temporary file, existing final output, decode error, or manifest mismatch.
- CI stops before XCTest if generation or provenance checks fail.
- CI stops before artifact upload if any of the five resources is absent from the application bundle.
- Runtime missing-resource and decode failures continue to stop the current session, clear timer and lock-screen state, and present an understandable error.
- Device validation failures are recorded with their exact conditions. A failed or interrupted long test is not reported as passed.

## Automated Verification

The implementation will run:

```bash
python3 -m unittest discover -s tools -p 'test_prepare_ios_audio.py' -v
```

It will then generate the ignored WAV files in the isolated worktree, run the full iOS XCTest suite on an available simulator, build the unsigned Release simulator app, inspect the bundle resources, and confirm the generated WAV paths are ignored and untracked.

Tests that write build products use temporary or DerivedData locations outside the repository. Generated WAV files are deleted from the disposable worktree when they are no longer needed; they are never staged.

## Documentation

The following documents will be updated with current-state language rather than rewriting old evidence:

- `docs/ios-development.md`: fresh-clone audio preparation and build instructions;
- `docs/ios-progress.md`: history cleanup consequences, repaired CI pipeline, and remaining physical tests;
- `docs/ios-validation.md`: exact automated and physical-device evidence;
- `README.md`: only if its current platform summary becomes inaccurate.

Substantial code fixes discovered during device validation also update `docs/progress.md` and `docs/validation.md` as required by the repository instructions.

## Success Criteria

This phase is complete when:

1. a fresh clone contains no generated rain WAV blob but can generate both derivatives with one documented command;
2. both derivative paths and their transcode temporary files are ignored, and neither derivative is tracked;
3. iOS CI generates audio, runs tests, builds the app, and refuses to upload an artifact missing any built-in sound;
4. the automated checks pass from the cleaned history;
5. physical-device smoke, two-boundary loop, lock-screen timer, background, route, import, persistence, and airplane-mode results are recorded accurately;
6. defects found in those checks are fixed or explicitly documented as blockers;
7. an eight-hour validation is completed or remains an explicitly scheduled final validation item;
8. no Personal Team setting, credential, private audio, generated rain WAV, or unrelated Android change is committed;
9. Git history is not rewritten.
