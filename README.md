# MeshStream P2P Flutter SDK

[简体中文](README.zh-CN.md) · [Website](https://meshstream.net/) · [Documentation](https://meshstream.net/docs/sdk/flutter-setup/) · [pub.dev](https://pub.dev/packages/meshstream_p2p) · [Live demo](https://demo.meshstream.net/)

MeshStream is a Flutter / Dart plugin for P2P video and audio streaming on Android and iOS. The `meshstream_p2p` package exposes the native playback URL, peer events and traffic statistics to `video_player` or another compatible player, with HTTP/CDN fallback.

The [example app](example/) uses `video_player`; your application owns the player UI and decoding.

## Features

- HLS, MPEG-DASH and HTTP Range MP4/MP3 through the native SDKs.
- A shared Dart client/session API for Android and iOS.
- Preload, playback position/buffer updates, peer events and P2P/CDN statistics.
- pub.dev installation and a `video_player` example app.

Media decoding and format support depend on your chosen player and platform. P2P availability depends on network conditions and peers with matching content.

## Requirements and installation

The Android dependency includes `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64` for matching devices and emulators. Your app must also meet the OS and architecture requirements of its framework and player.

Use Flutter 3.22 or newer and Dart 3.4 or newer. The plugin declares Android API 21+ and iOS 15.0+. Your app must meet the highest minimum OS version required by this plugin, the Flutter engine, and your player. The bundled example requires Android API 24+. Add `meshstream_p2p` and a player package such as `video_player` to your app. Install `meshstream_p2p` from pub.dev.

The plugin pins the public Android SDK `io.meshstream:meshstream-android-sdk:1.0.10`. Choose one configuration that matches how your project manages repositories. The examples below use Kotlin DSL.

### Default Flutter projects

Add the MeshStream repository to the existing `allprojects.repositories` block in `android/build.gradle.kts`, retaining the other repositories:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://sdk.meshstream.net/maven")
            content { includeGroup("io.meshstream") }
        }
    }
}
```

### Projects managing repositories in settings

Merge the following configuration into `dependencyResolutionManagement` in `android/settings.gradle.kts`. Set `PREFER_SETTINGS` explicitly so settings repositories take precedence. Retain Google, Maven Central, the Flutter engine repository, and any repositories required by your application:

```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
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
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

The [example manifest](example/android/app/src/main/AndroidManifest.xml) uses this configuration. If your app already has a network security config, merge these two loopback domains into it. An HTTP media origin needs its own explicit domain rule; prefer HTTPS. Do not enable app-wide cleartext traffic.

On iOS, use the normal Flutter CocoaPods flow after `flutter pub get`:

```sh
cd ios && pod install
```

The plugin podspec pins `MeshStreamKit` 1.0.10. The bundled example targets iOS 15.0 or newer with the current Flutter toolchain. In `ios/Runner/Info.plist`, set `NSAppTransportSecurity` → `NSAllowsLocalNetworking` to `true`, merging it into any existing ATS dictionary while retaining other restrictions.

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
flutter run --target lib/main.dart
```

Enter your own Key and an accessible source URL in the app. The fields contain only non-working hints. Add `-d DEVICE_ID` to select a connected device.

For a standalone Android Demo, run `flutter run --release --target lib/main.dart -d YOUR_ANDROID_DEVICE_ID`. To produce an APK, run `flutter build apk --release --target lib/main.dart`; the output is `build/app/outputs/flutter-apk/app-release.apk`. Configure your application's ID, version, and production signing before publishing it.

## Other MeshStream SDKs

- [Web](https://github.com/Mesh-Stream/meshstream-p2p-web-sdk): JavaScript / TypeScript, WebRTC and browser players.
- [iOS / macOS](https://github.com/Mesh-Stream/meshstream-p2p-ios-sdk): MeshStreamKit, Swift / Objective-C, SPM and CocoaPods.
- [Android](https://github.com/Mesh-Stream/meshstream-p2p-android-sdk): Kotlin / Java, Maven and Media3 / ExoPlayer.
- [Windows](https://github.com/Mesh-Stream/meshstream-p2p-Windows-sdk): C / C++ API for Windows 10 / 11 x64.
- [uni-app](https://github.com/Mesh-Stream/meshstream-p2p-uniapp-sdk): UTS / JavaScript plugin for iOS and Android apps.
- [React Native](https://github.com/Mesh-Stream/meshstream-p2p-react-native-sdk): TypeScript API for iOS / Android with react-native-video examples.
