# MeshStream Flutter SDK design

## Objective

Publish `meshstream_p2p` 1.0.0 to pub.dev: a Flutter binding for the MeshStream Android and iOS P2P playback SDKs. The package supplies P2P-accelerated playback URLs, but does not include or own a video player.

The initial release supports Android API 24+ and iOS 13+, requires Flutter 3.22+ and Dart 3.4+, and is contract-compatible with the React Native 1.0 SDK.

## Scope

The package has one public Dart API, one Android implementation, and one iOS implementation in a single repository and a single pub package. It does not ship Web, Windows, macOS, Linux, or a custom player.

The public models mirror the React Native contract:

- `MeshStreamConfig`: non-empty `key`, optional `p2pEnabled`.
- `PlaybackSessionOptions`: `url`, optional stable `contentId`, `mimeType`, and origin headers.
- `MeshStreamStatus`, `MeshStreamStats`, `MeshStreamDiagnostics`, `MeshStreamSessionInfo`, and `MeshStreamEvent`.
- Playback modes `NATIVE_P2P` and `NATIVE_CDN`.
- The complete MeshStream unavailable-reason enum from the React Native SDK.

## Public API and lifecycle

`MeshStream.create(MeshStreamConfig)` returns a `Future<MeshStreamClient>`. A client may own multiple independent sessions.

`MeshStreamClient.createPlaybackSession(PlaybackSessionOptions)` returns a `Future<MeshStreamPlaybackSession>`. A session exposes `clientId`, `sessionId`, `playbackUrl`, `playbackMode`, and optional `fallbackReason`. The caller supplies `playbackUrl` to its own player, such as `video_player`.

Sessions expose:

- `preload()`
- `setP2pEnabled(bool)`
- `updateBufferedDurationMs(int)`
- `updateCurrentPositionMs(int)`
- `getStats()`
- `getDiagnostics()`
- `close()`

Clients expose `getStatus()` and `close()`. Close operations are idempotent. Closing a client closes every session it owns; closing one client never affects another client in the same process. Operations after close fail locally with a stable closed-resource error.

`MeshStream.events` is a broadcast `Stream<MeshStreamEvent>`. A convenience filtered-stream API accepts optional `clientId`, `sessionId`, and event type. Every emitted event includes client and session identifiers and is one of: `peerCountChanged`, `playbackPrepared`, `p2pReady`, `p2pUnavailable`, `statistics`, `cdnFallback`, `trackerError`, or `peerConnectError`.

## Package layout

```text
lib/
  meshstream_p2p.dart
  src/
    meshstream.dart
    meshstream_client.dart
    meshstream_playback_session.dart
    models.dart
    pigeon/generated/
pigeons/meshstream_api.dart
android/src/main/kotlin/...
ios/Classes/...
example/
test/
```

The root library exports only the supported facade, client/session classes, models, events, and exception types. Generated bridge files remain internal.

## Bridge design

Pigeon is the sole source of truth for typed request/response messages and native operations. It defines host calls for creating and closing clients/sessions, preloading, toggling P2P, reporting player state, and reading status/statistics/diagnostics.

An `EventChannel` carries native asynchronous events into the Dart broadcast stream. This keeps event subscription and cancellation idiomatic in Flutter without putting long-lived callbacks into the request/response API.

Bridge errors become `MeshStreamException`, with stable codes including `CREATE_CLIENT_FAILED`, `CREATE_SESSION_FAILED`, `UNKNOWN_CLIENT`, and `UNKNOWN_SESSION`. Pigeon transport failures carry the originating native code/message/details without leaking platform-specific types to application code.

P2P unavailability is a successful CDN fallback, not an API failure. Session creation returns a playable CDN URL when necessary, along with `fallbackReason`; the event stream reports subsequent `p2pUnavailable` and `cdnFallback` signals.

## Android implementation

The Android plugin uses Kotlin and depends on `io.meshstream:meshstream-android-sdk:1.0.2`. Documentation instructs host applications to add the MeshStream Maven repository to Gradle dependency resolution. The plugin enforces `minSdk 24`.

The implementation owns concurrent maps from Flutter-visible client IDs to `P2pClient` instances and per-client session IDs to `PlaybackSession` instances. It converts native status, stats, diagnostics, playback modes, and unavailable reasons to the Pigeon models. Cleanup closes sessions first, then the owning client.

## iOS implementation

The iOS plugin uses Swift and its podspec depends on `MeshStreamKit = 1.0.2`, with deployment target iOS 13. CocoaPods resolves the native SDK during normal Flutter iOS installation; consumers run `pod install` as usual.

It maintains the same client/session ownership map and makes the same model, error, and lifecycle conversions as Android. Native-to-Dart event delivery occurs on the main queue.

## Event ordering and threading

A native SDK may emit an event while a new session is being returned across the bridge. Until the Flutter session mapping exists, each platform buffers at most eight events per native session and at most 64 native sessions. Once the mapping exists, buffered events are emitted in arrival order. Events for closed sessions are discarded.

Both implementations marshal EventChannel delivery onto their Flutter-safe main thread/queue. The Dart stream is broadcast so a telemetry view and playback controller can subscribe independently.

## Validation and testing

Dart unit tests cover model conversion, non-empty key/URL validation, non-negative playback values, filtered event streams, idempotent close, and behavior after close.

Android/JVM and iOS/XCTest tests cover bridge model mapping, status/statistics/diagnostics calculations, lifecycle cleanup, unknown-client/session errors, and event buffering/flush ordering.

The example app uses `video_player` and lets a developer provide a Key and source URL. It creates, preloads, and closes sessions, displays P2P mode, peer count, stats, fallback reason, and diagnostics. It serves as Android and iOS real-device regression coverage.

CI runs `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, an Android build, and iOS CocoaPods/build validation. Before publishing, release validation runs `flutter pub publish --dry-run`.

## Documentation and release

The repository includes English and Chinese README files, CHANGELOG, LICENSE, and CONTRIBUTING guide. The README includes installation from pub.dev, Android repository configuration, iOS setup, the smallest playable integration, resource lifecycle, events, and CDN fallback semantics.

No Key, private test media, or private binary is committed. The first release is `meshstream_p2p` version 1.0.0 on pub.dev, paired with a GitHub release of the same version.
