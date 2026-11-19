# iOS repository handoff

Applies to the whole repository. Inspect Git status first. Read `README.md`,
`docs/ios-development.md`, `docs/ios-progress.md` and `docs/ios-validation.md`
before changing code. Historical records describe the original monorepo;
use current README/build instructions for this standalone repository.

- This is the iOS repository, developed on macOS with Xcode. No Android checkout,
  Gradle or Android SDK is required. Preserve `ios/MinimalSleep.xcodeproj`, scheme
  `MinimalSleep`, iOS 17 minimum and bundle ID `io.github.resker666.minimalsleep`.
- Prepare generated M4A using `tools/prepare_ios_audio.py`; source Ogg files live
  in `assets/source-audio/`. Do not add cross-repository checkout dependencies.
- Preserve audio licensing, source hashes, strict output checks and the documented
  FFmpeg 9.0.2 reference environment. Generated M4A and temporary files stay ignored.
- Keep the app offline and preserve white noise alongside rain/ocean sounds.
  Recordings and imports stay in app-private storage, never Git or uploads.
- Preserve the separate recording development branch. Playback interference marks
  are not echo cancellation or proof of sound classification.
- Never commit Team IDs, certificates, provisioning profiles, credentials, local
  caches, generated apps or user audio.
- Run the iOS Python audio tests, then XCTest/build on macOS when available.
  Update iOS progress/validation with actual evidence and explicit environment limits.
  A successful build does not prove device audio, signing or overnight reliability.
