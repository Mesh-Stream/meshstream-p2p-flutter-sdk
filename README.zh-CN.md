# MeshStream P2P Flutter SDK

[English](README.md) · [官网](https://meshstream.net/zh/) · [接入文档](https://meshstream.net/zh/docs/sdk/flutter-setup/) · [pub.dev](https://pub.dev/packages/meshstream_p2p) · [在线 Demo](https://demo.meshstream.net/)

MeshStream 是面向 Android 和 iOS 的 Flutter / Dart P2P 视频与音频流媒体插件。`meshstream_p2p` 向 `video_player` 或其他兼容播放器提供原生播放地址、Peer 事件及流量统计，并支持 HTTP/CDN 回退。

[示例应用](example/)使用 `video_player`；播放器界面与解码由应用管理。

## 工作方式

把原始媒体地址交给 SDK 创建会话，再把会话的 `playbackUrl` 交给现有播放器：

```text
应用 → SDK 创建播放会话 → 本地播放地址 → 播放器
                            └─ SDK 从 Peer 或源站/CDN 获取媒体
```

播放器继续负责解码、画面和播放控制；SDK 负责媒体传输、缓存及 P2P 调度。服务配置与 P2P 准备在后台执行，不需要等到 Peer 连接后才开始播放。离开播放页或切换内容时，先停止使用旧播放地址，再关闭旧会话。

## 产品能力

- 通过原生 SDK 接入 HLS、MPEG-DASH 和支持 HTTP Range 的 MP4/MP3。
- Android 与 iOS 使用统一的 Dart client/session API。
- 支持预加载、播放位置与缓冲回传、Peer 事件和 P2P/CDN 统计。
- 通过 pub.dev 安装，提供 `video_player` 示例应用。

## 接入准备

- 在 [MeshStream 控制台](https://console.meshstream.net/)创建应用和对应平台的 SDK Key；启用身份校验时，登记与运行应用一致的包名或 Bundle ID。
- 准备一个可播放的 HLS `.m3u8`、DASH `.mpd`、支持 Range 的 MP4 或 MP3 地址，建议使用 HTTPS。
- 选择支持该媒体格式的播放器。SDK 提供传输能力，不增加播放器的解码能力；例如 AVPlayer 不原生支持 DASH。

希望先看效果？直接跳到[运行 Demo](#运行-demo)，再按下方步骤接入自己的应用。顶部的在线 Demo 是 Web 体验页，各端示例在本仓库中运行。

## 安装与网络配置

```bash
flutter pub add meshstream_p2p:1.1.1
flutter pub add video_player
```

插件版本为 `1.1.1`，Android 与 iOS 原生依赖均固定为 `1.1.1`。

Android 依赖包含 `armeabi-v7a`、`arm64-v8a`、`x86` 和 `x86_64`，可用于相应架构的真机与模拟器；应用仍需满足框架、基座及播放器的系统和架构要求。

需要 Flutter 3.22、Dart 3.4 或更新版本。插件 Android 声明下限为 API 21，iOS 为 15.0。应用实际下限取插件、Flutter 引擎和播放器要求的最大值；示例需要 Android API 24 及以上。

插件固定使用 Android SDK `io.meshstream:meshstream-android-sdk:1.1.1`。根据工程当前的仓库管理方式选择下面一种配置。以下示例使用 Kotlin DSL。

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

<details>
<summary>使用 settings 集中管理仓库的工程（可展开）</summary>

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

</details>

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

插件 podspec 固定使用 `MeshStreamKit` 1.1.1。仓库内示例在当前 Flutter 工具链下以 iOS 15.0 或更新版本为目标。在 `ios/Runner/Info.plist` 中设置 `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`，已有 ATS 字典时合并该设置并保留其他限制。

## 开始播放

将示例 Key 和 URL 换成你有权使用的值。`MeshStreamConfig` 与 `PlaybackSessionOptions` 是带校验的工厂构造函数，调用时不要加 `const`。

```dart
import 'package:meshstream_p2p/meshstream_p2p.dart';
import 'package:video_player/video_player.dart';

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

将该控制器交给组件的 `VideoPlayer(controller)` 渲染；以下片段分别放在页面初始化与退出流程中，不要创建后立即关闭会话。

```dart
// 退出页面时先取消事件订阅，再依次释放：
await controller.dispose();
await session.close();
await client.close();
```

## 运行 Demo

```sh
git clone https://github.com/Mesh-Stream/meshstream-p2p-flutter-sdk.git
cd meshstream-p2p-flutter-sdk/example
flutter pub get
flutter run --target lib/main.dart
```

在应用中输入自己的 Key 和可访问的源 URL。字段仅含无法工作的提示值。连接多个设备时添加 `-d 设备ID`。

需要独立运行 Android Demo 时，执行 `flutter run --release --target lib/main.dart -d YOUR_ANDROID_DEVICE_ID`，将设备 ID 替换为实际值。分发 APK 时执行 `flutter build apk --release --target lib/main.dart`，产物为 `build/app/outputs/flutter-apk/app-release.apk`。发布自己的应用前配置应用 ID、版本及正式签名。

先用 `flutter devices` 查看设备 ID。iOS 模拟器需要 macOS/Xcode；真机需配置签名。调试模式请从 `flutter run` 启动，避免直接从桌面重开调试应用。

## 事件与诊断

订阅 `MeshStream.eventsFor(sessionId: session.sessionId)`，并在关闭会话前取消订阅。事件名称为 `peerCountChanged`、`playbackPrepared`、`p2pReady`、`p2pUnavailable`、`statistics`、`cdnFallback`、`trackerError` 和 `peerConnectError`。`p2pUnavailable` 携带原因，`statistics` 携带字节计数及连接节点数。`cdnFallback` 表示 CDN 字节增量，不表示播放模式切换：原生 P2P 会话仍可能从 CDN 获取部分数据。会话提供 `getStats()` 和 `getDiagnostics()` 获取快照；客户端的 `getStatus()` 返回账户、应用、Key 和平台的可用状态。示例每五秒刷新统计和诊断，并显示最近的回退原因。

## 确认 P2P 生效

1. 在两台设备或两个可同时运行的实例中，用各自有效的 Key 播放同一内容，保持相同清晰度和相近播放进度。签名 URL 会变化时，为同一内容使用相同、稳定的内容 ID；不同内容不要共用 ID。
2. 查看 Demo 的 Peer 数和流量统计。Peer 大于 0 表示已连接节点；**P2P 下载或上传字节持续增加**才说明发生了媒体共享。
3. 关闭另一个实例，确认剩余实例仍能通过 HTTP/CDN 播放；然后测试拖动、切换内容和退出页面的释放流程。

只有一个观看者或没有可共享分片时，主要走 HTTP/CDN 属于正常情况。发现 Peer 及实际共享还取决于账户配置、网络连通性和双方缓存内容。

## 更多用法与支持

预加载、直播/点播调度、播放器状态回传、多会话及诊断，请参阅[高级用法](https://meshstream.net/zh/docs/sdk/flutter-advanced/)。更新记录见 [CHANGELOG](CHANGELOG.md)。接入问题请联系 support@meshstream.net，并附 SDK 版本、系统、播放器和脱敏日志。

## 其他 MeshStream SDK

- [Web](https://github.com/Mesh-Stream/meshstream-p2p-web-sdk): JavaScript / TypeScript、WebRTC 与浏览器播放器.
- [iOS / macOS](https://github.com/Mesh-Stream/meshstream-p2p-ios-sdk): MeshStreamKit、Swift / Objective-C、SPM 与 CocoaPods.
- [Android](https://github.com/Mesh-Stream/meshstream-p2p-android-sdk): Kotlin / Java、Maven 与 Media3 / ExoPlayer.
- [Windows](https://github.com/Mesh-Stream/meshstream-p2p-Windows-sdk): 面向 Windows 10 / 11 x64 的 C / C++ 接口.
- [uni-app](https://github.com/Mesh-Stream/meshstream-p2p-uniapp-sdk): 面向 iOS / Android App 的 UTS / JavaScript 插件.
- [React Native](https://github.com/Mesh-Stream/meshstream-p2p-react-native-sdk): 面向 iOS / Android 的 TypeScript API 及 react-native-video 示例.
