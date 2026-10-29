# MeshStream P2P for Flutter

MeshStream adds peer-assisted delivery to Flutter playback on Android and iOS. It creates a playback URL for your player and reports P2P/CDN status; it does not provide a player UI or decoder. The [example app](example/) uses `video_player`.

## Requirements and installation

Use Flutter 3.22 or newer and Dart 3.4 or newer. Android requires API 24 or newer; iOS requires 15.0 or newer. Add `meshstream_p2p` and a player package such as `video_player` to your app. Install `meshstream_p2p: 1.0.5` from pub.dev. The bundled example pins that exact public version for installation verification.

The plugin pins the public Android SDK `io.meshstream:meshstream-android-sdk:1.0.6`. Add the MeshStream Maven repository to your host app's dependency repositories (for Kotlin Gradle settings, for example):

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            val flutterStorageBaseUrl =
                System.getenv("FLUTTER_STORAGE_BASE_URL") ?: "https://storage.googleapis.com"
            url = uri("$flutterStorageBaseUrl/download.flutter.io")
            content { includeGroup("io.flutter") }
        }
        maven {
            url = uri("https://sdk.meshstream.net/maven")
            content { includeGroup("io.meshstream") }
        }
    }
}
```

MeshStream playback URLs use a local HTTP proxy. In an Android host app, allow cleartext traffic for loopback hosts only. Add `android:networkSecurityConfig="@xml/meshstream_network_security_config"` to `<application>` and create `res/xml/meshstream_network_security_config.xml`:

```xml
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain>127.0.0.1</domain>
        <domain>localhost</domain>
    </domain-config>
</network-security-config>
```

The [example manifest](example/android/app/src/main/AndroidManifest.xml) uses this configuration. If your app already has a network security config, merge these two loopback domains into it. An HTTP media origin needs its own explicit domain rule; prefer HTTPS. Do not enable app-wide cleartext traffic.

On iOS, use the normal Flutter CocoaPods flow after `flutter pub get`:

```sh
cd ios && pod install
```

The plugin podspec pins the public `MeshStreamKit` 1.0.7 pod. No private spec repository or bundled XCFramework path is needed. The bundled example targets iOS 15.0 or newer with the current Flutter toolchain.

## Start playback

Replace the instructional Key and URL with values you are authorized to use. `MeshStreamConfig` and `PlaybackSessionOptions` are validated factories, so call them without `const`.

```dart
final client = await MeshStream.create(
  MeshStreamConfig(key: 'key_your_meshstream_key'),
);
final session = await client.createPlaybackSession(
  PlaybackSessionOptions(
    url: 'https://cdn.example.com/live/playlist.m3u8',
    contentId: 'live-channel-42',
    mimeType: MeshStreamMimeType.m3u8,
  ),
);
final controller = VideoPlayerController.networkUrl(
  Uri.parse(session.playbackUrl),
);
await controller.initialize();
await controller.play();
```

Import `package:meshstream_p2p/meshstream_p2p.dart` and your chosen player package. Keep one session per active playback. The session owns the playback URL and native P2P resources; the client owns its sessions. When playback ends, cancel event subscriptions, dispose the player, then `await session.close()` and `await client.close()`. Closing a client also closes any sessions still owned by it, but explicit session closure keeps the playback lifecycle clear. Send the player's current position and buffered duration in milliseconds through `updateCurrentPositionMs` and `updateBufferedDurationMs` at a low rate (the example uses at most once per second). These calls inform native scheduling; do not send on every video frame.

Supported source types are HLS (`m3u8`), MPEG-DASH (`mpd`), MP4 (`mp4`), and MP3 (`mp3`) via `MeshStreamMimeType`. Playback capabilities still depend on the chosen player and platform. A content ID is optional; use a stable ID for the same content. The SDK can fall back to CDN delivery when P2P is unavailable. Play the returned `session.playbackUrl` in either mode and inspect `session.playbackMode` and `session.fallbackReason` for the initial state.

## Events and diagnostics

Subscribe to `MeshStream.eventsFor(sessionId: session.sessionId)` and cancel the subscription before closing the session. Event names are `peerCountChanged`, `playbackPrepared`, `p2pReady`, `p2pUnavailable`, `statistics`, `cdnFallback`, `trackerError`, and `peerConnectError`. `p2pUnavailable` supplies a reason; `statistics` supplies byte counters and peer counts. `cdnFallback` reports a CDN byte delta, not a playback mode transition: a native P2P session can still fetch some bytes from CDN. The session also offers `getStats()` and `getDiagnostics()` for snapshots. `getStatus()` on the client reports account/application/key/platform eligibility. The example refreshes stats and diagnostics every five seconds and displays the latest fallback reason.

## Run the example

```sh
cd example
flutter pub get
flutter run
```

Enter your own Key and an accessible source URL in the app. The fields contain only non-working hints. The example has widget tests that use fake backends and do not require service access.
