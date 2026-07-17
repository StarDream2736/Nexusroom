# 客户端编译与打包

本文说明如何在 Windows 上编译和打包 NexusRoom Flutter 桌面客户端。客户端通过 REST API 和应用 WebSocket 直接连接 NexusRoom 服务端，语音使用内置 RTC 信令，直播播放使用服务端输出的 HTTP-FLV。

本文适用于 `2.1.0`。客户端把账号设置、登录状态和房间缓存写入 `Nexusroom.exe` 同级的 `data` 目录。发布空白客户端时不要包含开发机生成的 data 目录；备份或迁移现有客户端时则应将整个 data 目录与 Release 文件一起复制。

## 1. 构建环境

需要安装：

- Windows 10 或 Windows 11 x64
- Flutter Stable，附带 Dart 3.x
- Visual Studio 2022，并安装“使用 C++ 的桌面开发”工作负载
- Windows 10/11 SDK、MSVC、CMake 和 Ninja
- Git
- Go 1.22 或更高版本，仅在重新构建 WireGuard Helper 时需要

检查环境：

```powershell
flutter doctor -v
flutter devices
go version
```

`flutter doctor -v` 中的 Windows toolchain 必须通过，`flutter devices` 应列出 `windows`。

## 2. 本地二进制依赖

Windows 发布目录需要以下文件：

| 文件 | 源位置 | 用途 |
| --- | --- | --- |
| `nexusroom-wg.exe` | `client/native/wg-helper/` | WireGuard 隧道辅助进程 |
| `wintun.dll` | `client/native/wg-helper/` | Wintun 驱动运行库 |
| `ffmpeg.exe` | `client/tools/` | 屏幕捕获和 RTMP 推流 |

顶层 CMake 配置会在这些文件存在时，把它们复制到 `Nexusroom.exe` 所在目录。`client/tools/ffmpeg.exe` 是本地依赖，已被 Git 忽略。

重新构建 WireGuard Helper：

```powershell
go install github.com/tc-hib/go-winres@latest
cd client\native\wg-helper
.\build.bat
```

构建前确认三个文件存在：

```powershell
Test-Path client\native\wg-helper\nexusroom-wg.exe
Test-Path client\native\wg-helper\wintun.dll
Test-Path client\tools\ffmpeg.exe
```

缺少 FFmpeg 不影响聊天和语音功能，但屏幕捕获推流不可用。缺少 WireGuard Helper 或 Wintun 时，客户端 VLAN 功能不可用。

## 3. 获取依赖和质量检查

在仓库根目录执行：

```powershell
cd client
flutter pub get
flutter analyze
flutter test
```

`pubspec.lock` 应提交到 Git，以固定应用依赖版本。`.dart_tool/`、`build/`、插件元数据和 Windows ephemeral 目录属于生成内容，不提交。

如果修改了 Drift、Riverpod 或 JSON 生成模型，再执行：

```powershell
dart run build_runner build --delete-conflicting-outputs
```

## 4. 开发运行

```powershell
cd client
flutter run -d windows
```

客户端首次启动时填写服务端地址，例如：

```text
http://192.0.2.10:8080
```

不要在地址末尾填写 `/api/v1`。客户端会自行拼接 REST、WebSocket 和媒体路径。

## 5. Release 编译

```powershell
cd client
flutter build windows --release
```

典型输出目录：

```text
client/build/windows/x64/runner/Release/
```

发布时必须整体分发 Release 目录，不能只复制 `Nexusroom.exe`。至少检查：

```powershell
$release = 'build\windows\x64\runner\Release'
Test-Path "$release\Nexusroom.exe"
Test-Path "$release\data\flutter_assets"
Test-Path "$release\nexusroom-wg.exe"
Test-Path "$release\wintun.dll"
Test-Path "$release\ffmpeg.exe"
```

压缩发布目录：

```powershell
Compress-Archive `
  -Path build\windows\x64\runner\Release\* `
  -DestinationPath NexusRoom-windows-x64.zip `
  -Force
```

## 6. 服务端接口适配检查

当前客户端与统一服务端使用以下契约：

| 功能 | 客户端请求 | 服务端入口 |
| --- | --- | --- |
| 健康检查 | `GET /ping` | Gin HTTP 服务 |
| 登录注册 | `/api/v1/auth/*` | 内置认证模块 |
| 房间和消息 | `/api/v1/rooms/*` | 内置房间和 SQLite 消息模块 |
| 应用事件 | `/ws?token=...` | 内置 WebSocket Hub |
| 语音 | `rtc.offer`、`rtc.answer`、`rtc.ice` | 内置 Pion SFU |
| ICE 配置 | `connected.payload.rtc.ice_servers` | 内置 STUN/TURN 配置 |
| 推流入口 | 房间 ingress 的 `rtmp_url` 和 `stream_key` | 内置 RTMP 服务 |
| 直播播放 | `GET /api/v1/stream/{streamKey}` | 内置 HTTP-FLV 输出 |
| VLAN | `/api/v1/rooms/{id}/vlan/*` | WireGuard 协调模块 |

客户端会等待 WebSocket 进入 connected 状态，并保证 `room.join` 先于 `rtc.offer` 发送。房间加入操作是幂等的，断线重连后会自动恢复加入状态和 RTC 协商。

最小联调步骤：

1. 浏览器或 PowerShell 请求 `http://SERVER:8080/ping`，确认业务码为 `20000`。
2. 客户端完成注册或登录，确认 WebSocket 进入 connected。
3. 两个客户端加入同一房间，测试静音、说话状态和双向语音。
4. 创建 ingress，用 FFmpeg 或 OBS 推流，确认房间内 HTTP-FLV 播放正常。
5. 在不同 NAT 网络下测试语音；直连失败时确认 TURN 3478/UDP 和 51000-51100/UDP 可达。

## 7. 清理构建产物

```powershell
cd client
flutter clean
```

如果 Flutter 工具进程异常退出，可在确认没有正在运行的构建后删除以下可再生目录：

```text
client/.dart_tool/
client/build/
client/windows/flutter/ephemeral/
```

不要删除 `client/tools/ffmpeg.exe`、WireGuard Helper 或 Wintun，除非准备重新获取这些打包依赖。

## 8. 常见问题

### Windows toolchain 不可用

重新运行 Visual Studio Installer，安装“使用 C++ 的桌面开发”、MSVC、CMake 和 Windows SDK，然后执行 `flutter doctor -v`。

### media_kit 原生依赖校验或下载失败

先确认代理和缓存目录可写，然后执行：

```powershell
flutter clean
flutter pub get
flutter build windows --release -v
```

若仍失败，保留详细日志并检查失败的是依赖下载还是 CMake 编译，不要直接删除源码目录中的原生依赖。

### 客户端能登录但语音无法连接

检查服务端公网 IP、3478/UDP、RTC 端口 50000-50050/UDP 和 TURN Relay 端口 51000-51100/UDP。再检查 WebSocket 的 connected 事件是否包含 `rtc.ice_servers`。

### data 目录无法创建

客户端需要对自身所在目录具有写权限。不要把便携版放入普通用户不可写的 `Program Files` 等受保护目录；建议解压到用户可写目录后运行。
