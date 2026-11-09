# MeshStream P2P Flutter SDK

[English](README.md) · [官网](https://meshstream.net/zh/) · [接入文档](https://meshstream.net/zh/docs/sdk/flutter-setup/) · [pub.dev](https://pub.dev/packages/meshstream_p2p) · [在线 Demo](https://demo.meshstream.net/)

MeshStream 是面向 Android 和 iOS 的 Flutter / Dart P2P 视频与音频流媒体插件。`meshstream_p2p` 向 `video_player` 或其他兼容播放器提供原生播放地址、Peer 事件及流量统计，并支持 HTTP/CDN 回退。

[示例应用](example/)使用 `video_player`；播放器界面与解码由应用管理。

## 产品能力

- 通过原生 SDK 接入 HLS、MPEG-DASH 和支持 HTTP Range 的 MP4/MP3。
- Android 与 iOS 使用统一的 Dart client/session API。
- 支持预加载、播放位置与缓冲回传、Peer 事件和 P2P/CDN 统计。
- 通过 pub.dev 安装，提供 `video_player` 示例应用。

媒体解码与格式兼容性取决于所选播放器和平台；P2P 可用性取决于网络条件及持有相同内容的 Peer。

## 环境与安装

Android 依赖包含 `armeabi-v7a`、`arm64-v8a`、`x86` 和 `x86_64`，可用于相应架构的真机与模拟器；应用仍需满足框架、基座及播放器的系统和架构要求。

需要 Flutter 3.22、Dart 3.4 或更新版本。插件 Android 声明下限为 API 21，iOS 为 15.0。应用实际下限取插件、Flutter 引擎和播放器要求的最大值；示例需要 Android API 24 及以上。在应用中加入 `meshstream_p2p` 和播放器依赖，例如 `video_player`。从 pub.dev 安装 `meshstream_p2p`。

插件固定使用 Android SDK `io.meshstream:meshstream-android-sdk:1.0.10`。根据工程当前的仓库管理方式选择下面一种配置。以下示例使用 Kotlin DSL。

### Flutter 默认工程

在 `android/build.gradle.kts` 已有的 `allprojects.repositories` 中添加 MeshStream 仓库，保留原有仓库：

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

### 使用 settings 集中管理仓库的工程

在 `android/settings.gradle.kts` 的 `dependencyResolutionManagement` 中合并下面的配置。显式设置 `PREFER_SETTINGS`，让 settings 中的仓库生效；同时保留 Google、Maven Central、Flutter 引擎及业务所需的仓库：

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

MeshStream 播放 URL 会使用本机 HTTP 代理。Android 宿主应用只需允许回环主机的明文流量：在 `<application>` 中设置 `android:networkSecurityConfig="@xml/meshstream_network_security_config"`，并创建 `res/xml/meshstream_network_security_config.xml`：

```xml
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

[示例 manifest](example/android/app/src/main/AndroidManifest.xml) 已引用该配置。如果应用已有网络安全配置，应将这两个回环域名合并进去。HTTP 媒体源需要单独添加明确的域名规则；优先使用 HTTPS。不要为整个应用开启明文流量。

iOS 在 `flutter pub get` 后按 Flutter 常规 CocoaPods 流程安装：

```sh
cd ios && pod install
```

插件 podspec 固定使用 `MeshStreamKit` 1.0.10。仓库内示例在当前 Flutter 工具链下以 iOS 15.0 或更新版本为目标。在 `ios/Runner/Info.plist` 中设置 `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`，已有 ATS 字典时合并该设置并保留其他限制。

## 开始播放

将示例 Key 和 URL 换成你有权使用的值。`MeshStreamConfig` 与 `PlaybackSessionOptions` 是带校验的工厂构造函数，调用时不要加 `const`。

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

导入 `package:meshstream_p2p/meshstream_p2p.dart` 和所选播放器包。每路活动播放使用一个会话。会话拥有播放 URL 与原生 P2P 资源；客户端拥有其会话。播放结束时，先取消事件订阅并释放播放器，再依次执行 `await session.close()`、`await client.close()`。关闭客户端也会关闭仍由它持有的会话，但显式关闭会话可使播放生命周期更清晰。以低频率用 `updateCurrentPositionMs` 和 `updateBufferedDurationMs` 回传播放器的当前位置和缓冲时长（毫秒）；示例最多每秒一次。这些数据用于原生调度，不要逐帧上报。

`MeshStreamMimeType` 支持 HLS (`m3u8`)、MPEG-DASH (`mpd`)、MP4 (`mp4`) 和 MP3 (`mp3`) 源。实际播放能力仍取决于所选播放器和平台。内容 ID 可选；同一内容建议使用稳定的 ID。P2P 不可用时 SDK 可回退到 CDN。两种模式都播放返回的 `session.playbackUrl`；通过 `session.playbackMode` 和 `session.fallbackReason` 查看初始状态。

## 事件与诊断

订阅 `MeshStream.eventsFor(sessionId: session.sessionId)`，并在关闭会话前取消订阅。事件名称为 `peerCountChanged`、`playbackPrepared`、`p2pReady`、`p2pUnavailable`、`statistics`、`cdnFallback`、`trackerError` 和 `peerConnectError`。`p2pUnavailable` 携带原因，`statistics` 携带字节计数及连接节点数。`cdnFallback` 表示 CDN 字节增量，不表示播放模式切换：原生 P2P 会话仍可能从 CDN 获取部分数据。会话提供 `getStats()` 和 `getDiagnostics()` 获取快照；客户端的 `getStatus()` 返回账户、应用、Key 和平台的可用状态。示例每五秒刷新统计和诊断，并显示最近的回退原因。

## 运行示例

```sh
cd example
flutter pub get
flutter run --target lib/main.dart
```

在应用中输入自己的 Key 和可访问的源 URL。字段仅含无法工作的提示值。连接多个设备时添加 `-d 设备ID`。

需要独立运行 Android Demo 时，执行 `flutter run --release --target lib/main.dart -d YOUR_ANDROID_DEVICE_ID`，将设备 ID 替换为实际值。分发 APK 时执行 `flutter build apk --release --target lib/main.dart`，产物为 `build/app/outputs/flutter-apk/app-release.apk`。发布自己的应用前配置应用 ID、版本及正式签名。

## 其他 MeshStream SDK

- [Web](https://github.com/Mesh-Stream/meshstream-p2p-web-sdk): JavaScript / TypeScript、WebRTC 与浏览器播放器.
- [iOS / macOS](https://github.com/Mesh-Stream/meshstream-p2p-ios-sdk): MeshStreamKit、Swift / Objective-C、SPM 与 CocoaPods.
- [Android](https://github.com/Mesh-Stream/meshstream-p2p-android-sdk): Kotlin / Java、Maven 与 Media3 / ExoPlayer.
- [Windows](https://github.com/Mesh-Stream/meshstream-p2p-Windows-sdk): 面向 Windows 10 / 11 x64 的 C / C++ 接口.
- [uni-app](https://github.com/Mesh-Stream/meshstream-p2p-uniapp-sdk): 面向 iOS / Android App 的 UTS / JavaScript 插件.
- [React Native](https://github.com/Mesh-Stream/meshstream-p2p-react-native-sdk): 面向 iOS / Android 的 TypeScript API 及 react-native-video 示例.
