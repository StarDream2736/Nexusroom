# Client

[完整的客户端编译与打包文档](../docs/build/client-build.md)

此目录包含 NexusRoom Flutter 桌面客户端和客户端专用依赖，不包含服务端或部署配置。

客户端通过应用 WebSocket 完成房间事件与 WebRTC 信令，使用 `flutter_webrtc` 直接连接 NexusRoom 内建语音 SFU。直播仍由 `media_kit` 播放服务端输出的 HTTP-FLV；屏幕捕获通过打包的 FFmpeg 推送 RTMP。

## 目录

```text
lib/                    Flutter/Dart 业务代码
test/                   客户端测试
windows/                Windows Runner 与打包配置
native/wg-helper/       WireGuard Windows 辅助进程
tools/                  FFmpeg 等本地构建工具
```

## 开发检查

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

发布构建：

```bash
flutter build windows --release
```

Windows 构建会从 `native/wg-helper/` 收集 `nexusroom-wg.exe` 和 `wintun.dll`，并从 `tools/` 收集 `ffmpeg.exe`。FFmpeg 是被 Git 忽略的本地打包依赖；WireGuard Helper 可由同目录源码重新构建。

本次媒体改造只替换客户端连接实现，不改变既有 UI 布局、配色、状态图标或 UI emoji。
