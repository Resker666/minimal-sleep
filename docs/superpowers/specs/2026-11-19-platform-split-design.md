# Android / iOS repository split

The user selected option A: keep `Resker666/minimal-sleep` for Android and create
`Resker666/minimal-sleep-ios` for iOS. Mac is the iOS development environment;
this migration does not add a macOS target.

## Scope and alternatives

- Selected: retain the Android repository identity and download links; extract iOS.
- Rejected alternative: create two new repositories and keep a third navigation archive.
- Preserve existing commit history without force-pushing or filtering the source.
- Keep the iOS playback baseline on the new main branch and preserve the unmerged
  `codex/ios-night-recording` work separately. Do not merge new app behavior as part
  of the split.
- Each current tree owns its build configuration, tests, audio inputs, manifests,
  license notices and instructions. Shared audio is copied with unchanged bytes.
- Preserve the `ios/` prefix, Xcode paths, bundle identifier, Android application ID
  and app version numbers. Change packaging/development paths only.
- Use `assets/source-audio/` for the iOS Ogg inputs. Generated M4A stays ignored.
- Keep existing artifact hash checks and FFmpeg version requirements.
- Prepare Android removal as a draft PR. Do not merge it until the iOS repository,
  its development branch and independent build checks are verified.

## Acceptance

Each repository can prepare assets and build without the other checkout.
Migration checks must compare app source and asset hashes to their original refs,
exercise the iOS audio generator in a directory without `app/`, and run the
available platform tests. Report unavailable SDK/toolchain checks explicitly.
No user recordings, certificates, local caches or app binaries are committed.

## Verified source refs

- Android / iOS playback baseline: `eea22b14acb46fb0f4e2e7e8d1fc728b1cbc3528`.
- iOS recording development: `95ab67906136e81041df685ed30dc47a113108cc`.
