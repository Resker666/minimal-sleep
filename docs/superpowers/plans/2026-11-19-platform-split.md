# Platform Split Implementation Plan

> For agentic workers: execute these tasks sequentially with superpowers:executing-plans.

**Goal:** Prepare independently buildable Android and iOS repositories.

**Architecture:** Preserve commit history and the existing `ios/` project layout.
Copy licensed audio inputs into the iOS tree, separate CI and documentation, and
retain the recording development branch without merging its behavior.

**Tech Stack:** Git, Kotlin/Gradle, Swift/Xcode, Python and FFmpeg.

**Spec:** `docs/superpowers/specs/2026-11-19-platform-split-design.md`.

## Global constraints

Keep app source behavior, identifiers, versions, asset bytes and licenses intact.
Do not force-push, merge Android removal, or include generated/user audio.

## Review focus

Fresh checkout without the other platform; ignored/generated audio; stale relative
documentation links; preserved recording branch; source and license provenance.

## Task 1: Standalone iOS baseline

- [ ] Add a real FFmpeg regression test that generates audio without `app/`; observe failure.
- [ ] Move the two Ogg inputs to `assets/source-audio/`; update generator, tests,
  workflow paths, manifests and current documentation.
- [ ] Remove Android source, Gradle, Android CI and Android-only tools/docs from the
  iOS current tree. Keep original histories reachable.
- [ ] Run Python tests, check resource hashes and unchanged Swift/Xcode source.
- [ ] Commit `codex/split-ios-main`.

## Task 2: Preserve recording development

- [ ] Create `codex/split-ios-night-recording` from the original recording head.
- [ ] Apply only Task 1 migration changes, preserving branch-specific iOS source,
  workflow package checks and validation history.
- [ ] Run Python tests; compare every original Swift/test/Xcode blob; commit.

## Task 3: Android-only draft

- [ ] Branch `codex/split-android-only` from the original main.
- [ ] Remove iOS tree, iOS-specific CI/tools/docs; separate README, notices,
  asset manifest and ignore patterns. Record migration status.
- [ ] Run remaining Python tests, verify Android source/build blobs unchanged,
  attempt Gradle checks if the environment supports them, and commit.

## Task 4: Publish and verify

- [ ] Review all three migration commits with a fresh reviewer.
- [ ] Create the public iOS repository and publish main plus recording branch.
- [ ] Confirm the new remote refs/trees and independent CI results.
- [ ] Open the Android cleanup draft PR, documenting validation and prerequisites.
- [ ] Report completed work and exact remaining access/build blockers.

## Execution notes

Option A authorizes migration preparation. Use isolated local clones; no changes
are made to the existing checkout. GitHub connector lacks repository creation;
browser currently requires sign-in. Complete preparation before asking for it.
