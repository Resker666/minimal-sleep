# Repository handoff for coding agents

This file applies to the whole repository. Read `README.md`, `docs/progress.md`, and `docs/validation.md` before changing code. Inspect Git status first. The released `v0.2.0-preview.1` is a development preview; M3–M5 and overnight validation remain incomplete.

## Build environment

- The repository contains the Gradle wrapper, source, tests, and generated audio, but **not** a JDK, Android SDK, Gradle caches, build outputs, or APKs. `.tools/` and `deliverables/` are ignored. A fresh clone on another computer must obtain its own JDK 17, Android SDK API 36, Build Tools 35, Gradle distribution, and Maven dependencies.
- In this existing Windows workspace, check whether `.tools/jdk/jdk17.0.20_10`, `.tools/android-sdk-ready`, `.tools/gradle/gradle-8.13`, and `.tools/gradle-home` still exist before downloading anything. See `docs/development-setup.md` for a verified offline command and the reason the cache needs `MINIMAL_SLEEP_MAVEN_PROXY` even with `--offline`.
- Do not treat a successful build as proof of overnight reliability or sound classification. The natural sounds are procedural approximations; their subjective phone sound has not yet been confirmed.

## Project constraints

- Keep the app offline and preserve the white-noise core alongside rain and ocean sounds. Recording and playback share a device; preserve playback intervals and interference marks without claiming echo removal.
- Recordings remain in the Android app's private storage. Do not copy them into the repository or upload them. Do not add credentials, local build caches, or APKs to Git.
- State only verified test results. Update `docs/validation.md` with evidence and `docs/progress.md` with incomplete work when making substantial changes.
