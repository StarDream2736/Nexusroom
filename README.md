# NexusRoom

[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)](https://github.com/StarDream2736/Nexusroom)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NexusRoom 是面向小型私有社群的自托管通信平台。桌面端使用 Electron、React、TypeScript 和 Chromium，服务端保持 Go 单体架构。

## 当前能力

桌面端未登录时显示紧凑认证窗口，可填写服务器地址并登录或注册；认证成功后同一窗口展开完整 UI，并在本机恢复登录会话。登录后可以查看、创建、通过邀请码加入、切换和退出房间；房间内可以加载历史文字、接收实时文字并发送图片。图片先上传到服务端，客户端再用当前会话鉴权获取 Blob 后显示。

语音使用服务端 WebRTC 信令和内建语音引擎。桌面端可以加入房间语音、静音，并显示成员在线和说话状态。房间直播入口可以创建和管理，播放器优先协商 WebRTC；协商或媒体检查失败后锁定 HTTP-FLV，只有刷新播放才会重新尝试 WebRTC。房间还可以启用 WireGuard VLAN，Windows 客户端通过同级 Helper 和 Wintun 建立隧道。

服务端同时提供 REST API、WebSocket、SQLite、WebRTC 语音、RTMP 接入、HTTP-FLV 和浏览器 WebRTC 播放、STUN/TURN、内嵌直播网页以及 WireGuard 协调。

## 架构和目录

```text
Nexusroom/
├── client/       Electron + React + TypeScript 桌面端
├── server/       Go 单体服务端、媒体模块和内嵌网页
├── deployment/   Docker、systemd、安装脚本和配置模板
└── docs/         技术规范、开发部署指南和构建文档
```

Electron 主进程负责窗口、SQLite 和受控原生进程；预加载脚本只暴露窄 IPC；React 渲染进程运行在 Chromium 隔离环境。客户端持久化数据库位于 `NexusRoom.exe` 同级的 `data\nexusroom.sqlite`，按服务器地址和账号隔离。发布 ZIP 不预置 `data` 目录，首次运行时自动创建。

## 快速开始

### Windows 客户端

需要 Windows x64、Node.js 和 npm。在 `client` 目录执行：

```powershell
cd client
npm ci
npm run dev
```

构建和打包：

```powershell
npm run build
npm run package:win
```

`npm run package:win` 生成 `client\release\NexusRoom-3.0.0-windows-x64.zip`。把 ZIP 解压到可写目录后运行；发布目录根部包含 `NexusRoom.exe`、`nexusroom-wg.exe` 和 `wintun.dll`，不包含业务 `data` 目录。

### 服务端

Docker 部署：

```bash
cd deployment
chmod +x scripts/*.sh
./scripts/install.sh
```

Linux 直接部署：

```bash
cd deployment
chmod +x scripts/*.sh
sudo ./scripts/install-direct.sh
```

本地开发：

```bash
cd server
cp ../deployment/templates/server.yaml.template config.yaml
go test ./...
go run ./cmd/server
```

客户端输入服务端 Origin，例如 `http://127.0.0.1:8080`，不要附加 `/api/v1`。

## 网络端口

服务端默认使用 8080/TCP（API、WebSocket、网页和 HTTP-FLV）、1935/TCP（RTMP）、3478/UDP（STUN/TURN）、50000-50050/UDP（WebRTC 直连）、51000-51100/UDP（TURN 中继）和 51820/UDP（WireGuard VLAN）。外部部署时只开放实际启用的端口，并为 HTTP 和 WebSocket 配置 TLS 入口。

## 文档

完整架构、协议、数据边界和发布门禁见 [文档中心](docs/README.md) 与 [技术规范](docs/NexusRoom.md)。客户端命令见 [客户端开发指南](docs/guides/client.md) 和 [客户端构建文档](docs/build/client-build.md)，服务端部署见 [安装与部署指南](docs/guides/deployment.md)。

## 许可证

MIT License
