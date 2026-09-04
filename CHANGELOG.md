# Changelog

All notable changes to `dojah-kyc-sdk-react-expo` are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.22] - 2026-09-04

### Fixed

- Fixed `Internal compiler error` on `:dojah-kyc-sdk-react-expo:compileReleaseKotlin`
  for Expo SDK 54 / React Native 0.81 apps. The Dojah Kotlin SDK is built with
  Kotlin 2.2.10 and its classes carry Kotlin metadata version `2.2.0`, which the
  Kotlin 2.1.20 compiler shipped by those releases cannot read. The config plugin
  now raises `android.kotlinVersion` to `2.2.10` during prebuild, and warns when
  a stale `android.kspVersion` pin would override the KSP release Expo derives
  from it.
- The config plugin no longer downgrades the Android Gradle Plugin. It previously
  pinned AGP to `8.9.1` with a resolution strategy `force`, which lowered hosts
  that ship something newer (React Native 0.81 uses AGP `8.11.0`). It now applies
  a `require` constraint, so `8.9.1` acts as a floor and a newer AGP is kept.
  Existing projects have the old `force` block replaced on the next prebuild.
- `android.enableJetifier` is no longer appended to `android/gradle.properties`
  on every `expo prebuild`. The plugin now sets it in place and collapses
  duplicates left behind by earlier versions.

## [0.1.21] - 2026-08-15

### Fixed

- Resolved an Android crash in Liveness/Selfie capture when the fragment view
  was destroyed before `captureReadyTimer` completed (for example on back
  navigation or other lifecycle changes). The timer could still resume and
  call `getBinding()` after `onDestroyView()`, which threw
  `IllegalStateException: Can't access the Fragment View's LifecycleOwner`.
- Fixed Face detection initialisation on the Selfie retake flow.

### Changed

- Upgraded the Android Kotlin SDK from `com.github.dojah-inc:sdk-kotlin:v0.4.0`
  to `v0.4.1`.

## [0.1.19] - 2026-08-03

### Fixed

- Fixed issue with empty ID config flow.
- Fixed a crash on Android when the verification flow launches over the React
  activity. On React Native 0.79 with the New Architecture,
  `ReactActivityDelegate.onUserLeaveHint` throws a `NullPointerException` when
  the React host is not yet available. The config plugin now injects a guarded
  `onUserLeaveHint` override into the host app's `MainActivity` during
  `expo prebuild`.

### Changed

- Refactored liveness image detection with Google ML Kit.
- Upgraded the Android Kotlin SDK to `com.github.dojah-inc:sdk-kotlin:v0.4.0`.

[0.1.22]: https://github.com/dojah-inc/dojah_kyc_sdk_rn_expo/releases/tag/v0.1.22
[0.1.21]: https://github.com/dojah-inc/dojah_kyc_sdk_rn_expo/releases/tag/v0.1.21
[0.1.19]: https://github.com/dojah-inc/dojah_kyc_sdk_rn_expo/releases/tag/v0.1.19
