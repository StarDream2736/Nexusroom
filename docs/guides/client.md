# 客户端开发指南

本文档说明 NexusRoom `2.1.0` Flutter 桌面客户端的职责、目录、运行方式和本地数据约定。完整系统设计见 [NexusRoom 技术规范](../NexusRoom.md)，发布构建见 [客户端编译与打包](../build/client-build.md)。

## 客户端职责

- 通过 REST API 完成服务器探测、认证、用户、房间、好友、文件、推流入口和 VLAN 操作。
- 通过应用 WebSocket 接收房间事件、聊天确认、在线状态和 WebRTC 信令。
- 使用 `flutter_webrtc` 连接 NexusRoom 内建语音 SFU。
- 使用 `media_kit` 播放服务端输出的 HTTP-FLV。
- 调用随客户端分发的 FFmpeg 完成桌面捕获和 RTMP 推流。
- 调用 WireGuard Helper 管理 Windows 本地虚拟网卡。

## 目录

```text
client/
├── lib/app/                    应用外壳、主题和共享组件
├── lib/core/                   数据库、网络、原生服务和公共状态
├── lib/features/               按业务功能划分的页面、仓库和 Provider
├── native/wg-helper/           WireGuard Windows 辅助进程源码
├── test/                       客户端自动化测试
├── tools/                      FFmpeg 等本地构建依赖
└── windows/                    Windows Runner 与 CMake 配置
```

## 开发检查

```powershell
cd client
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run -d windows
```

生成 Windows Release：

```powershell
flutter build windows --release
```

## 本地数据

账号设置、服务器地址、登录令牌、音频设备选择和房间消息缓存统一保存在 `Nexusroom.exe` 同级的 `data\nexusroom.sqlite`。消息主键包含服务器 URL、账号 ID 和消息 ID，防止同一台电脑上的不同账号读取彼此缓存。

客户端不会扫描或导入其他系统目录中的数据库。需要在设备之间转移本地状态时，应先关闭客户端，再复制完整的 `data` 目录。

“清除本地数据”会在数据库连接保持打开的情况下事务性清空设置表和消息表，然后执行数据库压缩并返回服务器设置页。该操作不得删除 `data` 目录、关闭全局数据库连接或强制终止进程。

## UI 和状态

- 明暗主题必须通过 `ThemeData` 和 `NexusColors` 上下文令牌读取；不得新增可变静态颜色。
- 所有已挂载组件必须在主题切换时同步重建和过渡。
- 状态使用文字、颜色和 Material 矢量图标。
- 成员在当前房间内时显示常亮绿色中心点，不在房间内时显示暗色点。
- 检测到语音输入时中心点继续常亮，只允许外层光晕进行呼吸动画。
- 麦克风按钮必须以实际 RTC/ICE 状态为准，失败时恢复原状态并提供错误反馈。

## 消息规则

客户端只有在 WebSocket 已确认 `room.joined` 后才能发送房间消息。发送请求携带唯一 `client_message_id`；只有服务端完成持久化并通过 `chat.message` 回显后，客户端才把消息视为成功。`chat.error` 必须关联同一 `client_message_id` 并向用户显示失败原因。

图片和文件采用两步流程：先通过 REST API 上传并取得受保护的文件 URL，再通过 WebSocket 发送 `image` 或 `file` 类型消息及元数据。

## 原生依赖

Windows 构建会收集 `nexusroom-wg.exe`、`wintun.dll` 和 `ffmpeg.exe`。缺失任一实际使用的二进制时，相关功能必须显示明确错误，不能静默失败。网络图片只使用进程内缓存，不在系统缓存目录写入账号相关持久化数据。
