# Client

[完整的客户端编译与打包文档](../docs/build/client-build.md)

此目录包含 NexusRoom Flutter 桌面客户端和客户端专用依赖，不包含服务端或部署配置。

当前客户端版本为 `2.0.0`。

客户端通过应用 WebSocket 完成房间事件与 WebRTC 信令，使用 `flutter_webrtc` 直接连接 NexusRoom 内建语音 SFU。直播仍由 `media_kit` 播放服务端输出的 HTTP-FLV；屏幕捕获通过打包的 FFmpeg 推送 RTMP。

文字和图片消息只有在 WebSocket 已确认加入房间、且服务端完成持久化并回显后才显示为发送成功。麦克风在 RTC 建连前恢复持久化设备选择，并在开关麦失败时保留原状态和显示错误。

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

客户端 2.x 保留原有页面分区，统一使用简洁的深色桌面视觉体系。在线、离线、语音和推流状态由文字、颜色与 Material 矢量图标表达，不使用 emoji。

房间语音会等待 RTC 与 ICE 实际连通后再开放麦克风；断线状态下点击麦克风按钮会自动重连。推流入口同时提供服务器地址、推流密钥和经过校验的完整发布地址。
