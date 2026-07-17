# NexusRoom

[![Version](https://img.shields.io/badge/version-2.1.0-blue.svg)](https://github.com/StarDream2736/Nexusroom)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NexusRoom 是面向小型私有社群的自托管通信平台，包含即时消息、多人语音、RTMP 直播、网页播放、文件共享和 WireGuard 虚拟局域网。

当前服务端采用单体架构：一个 Go 进程同时提供 REST API、WebSocket 信令、SQLite 持久化、Opus 语音 SFU、RTMP 接入、HTTP-FLV/WebRTC 播放、STUN/TURN、静态网页和 WireGuard 协调。部署不再依赖 PostgreSQL、Redis、LiveKit Server、SRS 或 nginx。

## 主要功能

- 房间消息、图片和文件传输，支持本地离线缓存、房间加入确认和发送结果确认。
- NexusRoom 内建 WebRTC 语音频道、开关麦、音频设备选择和说话状态同步。
- OBS 或客户端 FFmpeg 通过 RTMP 推送 H.264 视频；OBS AAC 音频由 HTTP-FLV 保留。
- 桌面端使用 HTTP-FLV 播放，浏览器优先使用 WebRTC 并支持 FLV 回退。
- 房间级 WireGuard 虚拟局域网。
- SQLite 嵌入式持久化，无外部数据库和数据迁移步骤。
- Docker 单容器部署和直接 Linux/systemd 部署。

## 仓库结构

```text
Nexusroom/
├── client/       Flutter 桌面客户端及客户端专用原生依赖
├── server/       Go 服务端、媒体核心和内嵌网页
├── deployment/   Docker、systemd、安装脚本和配置模板
└── docs/         统一技术规范、开发部署指南和构建文档
```

## 快速开始

Docker 部署：

```bash
cd deployment
chmod +x scripts/*.sh
./scripts/install.sh
```

直接 Linux 部署：

```bash
cd deployment
chmod +x scripts/*.sh
sudo ./scripts/install-direct.sh
```

客户端开发：

```bash
cd client
flutter pub get
flutter run -d windows
```

服务端开发：

```bash
cd server
cp ../deployment/templates/server.yaml.template config.yaml
# 将模板占位符替换为本地值
go test ./...
go run ./cmd/server
```

## 网络端口

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| 8080 | TCP | API、WebSocket、网页、HTTP-FLV |
| 1935 | TCP | RTMP 推流 |
| 3478 | UDP | STUN/TURN |
| 50000-50050 | UDP | WebRTC 直连媒体 |
| 51000-51100 | UDP | TURN 中继 |
| 51820 | UDP | WireGuard |

全部公开技术文档统一由 [文档中心](docs/README.md) 导航。详细配置见 [安装与部署指南](docs/guides/deployment.md) 和 [技术规范](docs/NexusRoom.md)；编译发布步骤见 [客户端编译文档](docs/build/client-build.md) 与 [服务端编译打包文档](docs/build/server-build.md)。

## 参与和安全

- 开发流程与提交规范：[CONTRIBUTING.md](CONTRIBUTING.md)
- 行为准则：[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 安全问题报告：[SECURITY.md](SECURITY.md)
- 版本历史：[CHANGELOG.md](CHANGELOG.md)

## 许可证

MIT License
