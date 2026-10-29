# Changelog

## 1.0.5

- Upgrade the public iOS dependency to MeshStreamKit 1.0.7 (iOS 15+).
- Upgrade the public Android dependency to meshstream-android-sdk 1.0.6.

## 1.0.4

- Upgrade the public iOS `MeshStreamKit` and Android `meshstream-android-sdk` dependencies to 1.0.4.
- Verify playback, peer discovery, P2P transfer, and cleanup with both 1.0.4 native SDKs on iOS and Android simulators; see [the validation record](docs/validation/2026-10-25-native-1.0.4-simulator-interop.md).
- The bundled example pins the published `meshstream_p2p: 1.0.0` package and verifies iOS↔iOS, Android↔Android, and iOS↔Android peer traffic; see [the peer matrix](docs/validation/2026-10-26-pubdev-peer-matrix.md).

## 1.0.0

- Android and iOS native SDK integration.
- Typed Dart configuration, playback session, status, statistics, and diagnostics APIs.
- P2P playback with CDN fallback when peer delivery is unavailable.
- Session-scoped events for peers, playback readiness, fallback, statistics, and errors.
- A `video_player` example app with lifecycle and telemetry handling.
