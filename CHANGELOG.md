# Changelog

All notable changes to `dojah-kyc-sdk-react-expo` are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.19]: https://github.com/dojah-inc/dojah_kyc_sdk_rn_expo/releases/tag/v0.1.19
