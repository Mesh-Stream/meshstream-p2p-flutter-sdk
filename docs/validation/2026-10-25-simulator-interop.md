# Flutter iOS/Android 模拟器联调验收（2026-10-25）

结果：通过。使用用户授权的两个平台 Key、同一个应用和公开 HLS 媒体列表，
在本机同时运行尚未发布的 Flutter 插件。两端均实际播放、发现对端并交换 P2P 数据。
本记录覆盖模拟器；未执行真机验收、GitHub 发布或 pub.dev 发布。

## 版本和环境

- Flutter 插件：`1.0.0`，源码基线 `d6e240d`，分支 `codex/flutter-sdk-implementation`，包含本次未提交的测试和示例配置更新。
- iOS：公开 CocoaPods `MeshStreamKit 1.0.2`，iPhone 18 Pro 模拟器，iOS 27.0，arm64。
- Android：公开 Maven `io.meshstream:meshstream-android-sdk:1.0.2`，Android API 35 ARM64 模拟器。
- Apple Silicon Mac，macOS 27.0，Xcode 27.1 (27A9275)。
- Flutter 3.47.8 stable (`737ba8f885`)、Dart 3.13.7、CocoaPods 1.17.0。
- JDK 17.0.21、Gradle 8.14、AGP 8.11.1、Kotlin 2.2.20、NDK 27.2.12479018、compile SDK 36。
- 测试源：`https://test-streams.mux.dev/x36xhzz/url_2/193039199_mp4_h264_aac_ld_7.m3u8`。
- 双端 content ID 相同，未使用假后端、自建 Tracker 或本地原生二进制。

## 最终同步运行结果

北京时间 2026-10-25 23:28–23:32，每端持续采样 180 秒，每 5 秒一次。
每端共 36 次采样，其中 33 次记录到 1 个 peer。

| 检查 | iOS | Android |
| --- | ---: | ---: |
| 实际播放 | 通过，320×184 | 通过，320×184 |
| 最大记录播放进度 | 175030 ms | 175176 ms |
| 最大 connected peers | 1 | 1 |
| 首次连接耗时（原生诊断） | 9009 ms | 14992 ms |
| 有 peer 的采样跨度 | 160 秒 | 160 秒 |
| P2P 下载 | 1,343,260 bytes | 770,988 bytes |
| P2P 上传 | 771,093 bytes | 1,343,745 bytes |
| CDN 下载 | 14,817,408 bytes | 6,951,488 bytes |
| ICE 尝试 / 成功 / 失败 | 1 / 1 / 0 | 1 / 1 / 0 |
| Tracker / peer 错误 | 0 / 0 | 0 / 0 |
| player / session / client 关闭 | 通过 | 通过 |
| 集成测试退出码 | 0 | 0 |

采样期间授权状态为 `OK`、P2P 有效，播放持续前进且播放器未报告错误。
CDN 和 P2P 字节分别记录；本次未注入 Tracker 断网故障。
iOS 单端预热阶段在无对端时也持续播放约 3 分钟，媒体通过 CDN 获取。

## 检查和复现

- `flutter analyze`：通过；插件测试 39 项、示例回归测试 4 项通过。
- iOS 模拟器构建、Android ARM64 APK 构建均通过。
- `integration_test/live_interop_test.dart`：最终双端同步运行均通过。
- 复现命令见 `example/integration_test/README.md`。Key 通过 Git 外的私有 JSON 文件传入，未写入测试源码或本记录；含 Key 的构建产物不应提交或发布。
- 完整脱敏 JSONL、命令日志和环境记录保存在 P2PCDN 本地忽略目录 `.runtime/flutter-validation/`。

## 本机适配与采集处理

- 将 Flutter 的 JDK 从 Android Studio 内置 JDK 25 切换到本机 JDK 17，解决 Gradle 8.14 不兼容。
- 示例固定已有的 NDK 27.2。本次 Flutter 对插件 NDK 声明有版本提示，实际构建与运行通过。
- 当前 Flutter 自动将示例升级至 iOS 15.0 最低版本和 UIScene 生命周期；此结论不覆盖 iOS 13/14。
- ARM64 ADB 37.0.1 发生 `libunwind` / SIGABRT，导致首轮 Android 采集断开。隔离使用官方 ADB 35.0.2 x86_64 服务经 Rosetta 重跑后双端均正常结束，未替换系统 Android SDK 的 ADB。
- SDK 的 Dart API 和双端 bridge 实现未修改；没有重新编译或发布原生 SDK。

## 原生依赖校验

- CocoaPods Apple ZIP SHA-256：`3cc6edd0fd3bbd4f1edc507c5c86d7634d92cb6291f75b777686b03445e51d35`，由 CocoaPods 安装流程校验。
- 实际解析的 Android AAR SHA-256：`6d1d4b62684acb73a54db24158f2cd94f5d9cc2f09eaf11641bc6cfada75018c`。
