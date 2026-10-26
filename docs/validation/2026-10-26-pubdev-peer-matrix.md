# pub.dev Demo 三组 peer 联调（2026-10-26）

结果：通过。使用已发布的 Flutter 包 `meshstream_p2p: 1.0.0` Demo，分别验证
iOS↔iOS、Android↔Android、iOS↔Android。三组均实际发现 peer、持续播放并交换
P2P 媒体字节；每端测试退出码均为 0，清理流程均完成。

## 测试范围

- Flutter 包：pub.dev `meshstream_p2p: 1.0.0`，锁文件使用 hosted source，归档 SHA-256 为 `cdfe016e2b2fe7f90c8385016f0abbafeae00164ba158907d1c7484634e8b810`。
- 原生依赖：iOS `MeshStreamKit 1.0.4`、Android `io.meshstream:meshstream-android-sdk:1.0.4`。
- iOS：iPhone 18 Pro 与 iPhone 18 Pro Max，iOS 27.0，arm64 模拟器。
- Android：两个 Android API 35 ARM64 模拟器，ADB 通过 Rosetta 使用隔离的 platform-tools 35.0.2 服务。
- 媒体源：`https://test-streams.mux.dev/x36xhzz/url_2/193039199_mp4_h264_aac_ld_7.m3u8`。
- 每端持续 180 秒、每 5 秒采样；同一组使用同一 content ID。没有真机参与。

## 结果

| 组合 / 端点 | 有 peer 的采样 | 最大 peer | 首次连接 | P2P 下载 | P2P 上传 | 最大播放进度 | 错误 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| iOS↔iOS / iPhone 18 Pro | 34 / 36 | 1 | 8009 ms | 3,208,032 B | 2,399,954 B | 175037 ms | 0 / 0 |
| iOS↔iOS / iPhone 18 Pro Max | 34 / 36 | 1 | 8005 ms | 2,399,444 B | 3,208,557 B | 175031 ms | 0 / 0 |
| Android↔Android / emulator-5554 | 34 / 36 | 1 | 9159 ms | 0 B | 1,336,820 B | 175855 ms | 0 / 0 |
| Android↔Android / emulator-5556 | 35 / 36 | 1 | 3989 ms | 1,336,680 B | 0 B | 175154 ms | 0 / 0 |
| iOS↔Android / iPhone 18 Pro | 34 / 36 | 1 | 3000 ms | 338,776 B | 391,451 B | 175039 ms | 0 / 0 |
| iOS↔Android / emulator-5554 | 33 / 36 | 1 | 11993 ms | 391,416 B | 339,276 B | 175166 ms | 0 / 0 |

“错误”列为 `trackerErrors / peerConnectErrors` 的最大采样值。所有端点的
`effectiveP2pEnabled` 均为 true，ICE 均为 1 次尝试、1 次成功、0 次失败，
播放器没有报告错误，session/client 关闭均为 true。

## 说明

- Android 首次共享工程并行启动时触发了 Gradle `kernel_blob.bin` 资源竞争；随后将两个 Demo 复制到隔离临时工程重新运行，三组结果只采用隔离重跑数据。
- iOS↔Android 组中 iOS 最后一个采样短暂显示 0 peer，但该端最大 peer 为 1、34 次采样有 peer，测试断言和退出码均通过。
- 本次只完成模拟器验收；iOS 真机验收和 Android 真机验收待完成。
- GitHub 推送和版本标签未执行；本次使用已发布的 pub.dev 1.0.0，未重新发布新版本。
