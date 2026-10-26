# MeshStream P2P Flutter SDK

MeshStream 为 Android 和 iOS 上的 Flutter 播放增加 P2P 辅助分发。它向播放器提供播放 URL，并报告 P2P/CDN 状态；它本身不提供播放器界面或解码器。[示例应用](example/)使用 `video_player`。

## 环境与安装

需要 Flutter 3.22、Dart 3.4 或更新版本。Android 最低 API 24，iOS 最低 13.0。在应用中加入 `meshstream_p2p` 和播放器依赖，例如 `video_player`。仓库内示例固定使用已发布的 `meshstream_p2p: 1.0.0`，用于验证公网包安装链路。

插件固定使用公开的 Android SDK `io.meshstream:meshstream-android-sdk:1.0.4`。将 MeshStream Maven 仓库加入宿主应用的依赖仓库配置，例如 Kotlin Gradle settings：

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
            url = uri("https://pub-61830e1369904d19af505ff74fd55ba4.r2.dev/maven")
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
        <domain>127.0.0.1</domain>
        <domain>localhost</domain>
    </domain-config>
</network-security-config>
```

[示例 manifest](example/android/app/src/main/AndroidManifest.xml) 已引用该配置。如果应用已有网络安全配置，应将这两个回环域名合并进去。HTTP 媒体源需要单独添加明确的域名规则；优先使用 HTTPS。不要为整个应用开启明文流量。

iOS 在 `flutter pub get` 后按 Flutter 常规 CocoaPods 流程安装：

```sh
cd ios && pod install
```

插件 podspec 固定使用公开的 `MeshStreamKit` 1.0.4 pod，无需私有 spec 仓库或本地 XCFramework 路径。仓库内示例在当前 Flutter 工具链下以 iOS 15.0 或更新版本为目标。

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
flutter run
```

在应用中输入自己的 Key 和可访问的源 URL。字段仅含无法工作的提示值。示例的 widget 测试使用假后端，不需要访问服务。
