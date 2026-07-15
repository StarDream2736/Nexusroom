# NexusRoom

> 专为小型私有圈子设计的自托管集成通讯平台

[![Version](https://img.shields.io/badge/version-1.8.3-blue.svg)](https://github.com/StarDream2736/Nexusroom)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 功能特性

- **即时通讯 (IM)** — 房间内文字消息、图片发送、历史记录离线同步
- **多人语音** — LiveKit WebRTC 语音频道、自由开关麦、说话状态指示
- **RTMP 推流直播** — SRS 6 接收推流，HTTP-FLV 分发，media_kit 播放
  - 应用内屏幕捕获推流（FFmpeg 驱动，支持全屏/指定屏幕、可配分辨率/帧率/码率）
  - OBS 直推支持
- **虚拟局域网 (VLAN)** — 内嵌 WireGuard，一键组建及管理局域网联机
- **Web 管理后台** — 超管面板、用户管理、房间管理
- **好友系统** — 通过数字 ID 添加好友，邀请进房间

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    【 客户端层 Client Layer 】               │
│              Flutter Desktop App (Windows / macOS)          │
│   UI · WebSocket Client · LiveKit SDK · media_kit · FFmpeg  │
│               SQLite 本地缓存 · WireGuard-go                 │
└──────────────────────┬──────────────────────────────────────┘
                       │  HTTPS / WSS / WebRTC  (OBS→SRS: RTMP)
┌──────────────────────▼──────────────────────────────────────┐
│                    【 服务端层 Server Layer 】               │
│                                                             │
│   Golang Main Server    LiveKit Server    SRS 6             │
│   REST API · WebSocket  SFU · 语音        RTMP→HTTP-FLV     │
│                                                             │
└──────────────────────┬──────────────────────────────────────┘
                       │  SQL / Redis Protocol
┌──────────────────────▼──────────────────────────────────────┐
│                    【 数据层 Data Layer 】                   │
│        PostgreSQL (持久化)        Redis (缓存·会话·在线状态)  │
└─────────────────────────────────────────────────────────────┘
```

## 快速开始

### 服务端部署

```bash
# 1. 克隆仓库并进入独立部署目录
git clone https://github.com/StarDream2736/Nexusroom.git
cd Nexusroom/deployment

# 2. 运行一键部署脚本（自动生成配置、拉取镜像、启动服务）
chmod +x scripts/install.sh
./scripts/install.sh

# 3. 配置防火墙（按需开放端口）
sudo ufw allow 8080/tcp          # API 服务
sudo ufw allow 8881/tcp          # 网页直播入口（独立）
sudo ufw allow 1935/tcp          # SRS RTMP 推流
sudo ufw allow 8883/tcp          # SRS RTMP 推流别名
sudo ufw allow 8000/udp          # SRS WebRTC 媒体
sudo ufw allow 7880/tcp          # LiveKit 信令
sudo ufw allow 7881/tcp          # LiveKit TCP 穿透
sudo ufw allow 3478/udp          # TURN 服务器
sudo ufw allow 50000:50050/udp   # WebRTC 媒体
sudo ufw allow 51820/udp         # WireGuard VPN
```

### 客户端编译

```bash
cd client
flutter pub get
flutter run -d windows        # 调试
flutter build windows --release  # 发布
```

## 端口说明

| 端口 | 协议 | 服务 | 说明 |
|------|------|------|------|
| 8080 | TCP | Golang 主服务 | REST API + WebSocket + FLV 反向代理 |
| 8881 | TCP | Golang 主服务 | 网页直播入口（独立于桌面客户端） |
| 1935 | TCP | SRS 6 | RTMP 推流接收（OBS） |
| 8883 | TCP | SRS 6 | RTMP 推流别名端口（网页直播场景） |
| 8000 | UDP | SRS 6 | WebRTC 媒体传输 |
| 7880 | TCP | LiveKit | WebRTC 信令（语音） |
| 7881 | TCP | LiveKit | TCP 穿透备用 |
| 3478 | UDP | LiveKit TURN | ICE 穿透 |
| 50000-50050 | UDP | LiveKit | WebRTC 媒体流 |
| 51820 | UDP | WireGuard | VLAN 虚拟局域网 |
| 3000 | TCP | Web 管理后台 | 可选 |

## 系统要求

### 服务端

- Docker 20.10+ / Docker Compose 2.0+
- 1 核 CPU / 2 GB 内存即可（SRS 无转码，CPU 占用极低）

### 客户端

- Windows 10+ / macOS 11+ / Linux
- Flutter 3.x SDK

## 项目结构

```
nexusroom/
├── client/                    # Flutter 客户端源码与客户端专用依赖
│   ├── native/wg-helper/      # Windows WireGuard 辅助进程
│   └── tools/                 # FFmpeg 等本地构建工具（大文件不入库）
├── server/                    # Go 服务端源码
├── deployment/                # 安装与部署，不放业务源码
│   ├── scripts/               # 安装脚本
│   ├── templates/             # 可提交的配置模板
│   └── config/                # 生成配置；仅静态 nginx.conf 入库
└── docs/                      # 技术文档与变更记录
```

各目录可独立进入和维护：

- [客户端开发说明](client/README.md)
- [服务端开发说明](server/README.md)
- [安装部署说明](deployment/README.md)
- [文档索引](docs/README.md)

## 最近开发记录

### 2026-07-15：开发环境与目录结构整理

- 将 Flutter 客户端、Go 服务端、安装部署文件和项目文档拆分为四个独立维护区域。
- 将 WireGuard helper 移入 `client/native/wg-helper/`，将 FFmpeg 移入 `client/tools/`，客户端依赖不再散落于仓库根目录。
- 将原 `deploy/` 重组为 `deployment/scripts/`、`deployment/templates/` 和 `deployment/config/`，模板、脚本、运行配置与数据分别管理。
- 安装脚本支持 `docker compose` 与 `docker-compose`，并可从任意工作目录调用。
- SRS 配置改由模板生成，新部署会自动写入服务器公网 IP，不再依赖仓库中的固定 candidate。
- 为客户端、服务端、部署和文档目录补充独立 README，并更新全部路径引用。
- 清除非 UI 文本中的 Emoji；UI 规范和示意图中承担状态表达的图标保持不变。
- 已通过 Go 模块编译检查、Docker Compose 配置校验和 Flutter Windows Release 构建验证。

完整记录见 [2026-07-15 开发环境整理记录](docs/development/2026-07-15-environment-reorganization.md)。

## 开发路线图

- [x] 第一阶段：基础设施 + IM
- [x] 第二阶段：音视频集成（LiveKit 语音 + SRS 推流）
- [x] 第三阶段：应用内屏幕捕获推流 + 虚拟局域网（VLAN）
- [ ] 第四阶段：管理功能增强与扩展接口
- [ ] 第五阶段：屏幕共享与远程协作

## 许可证

MIT License

## 致谢

- [LiveKit](https://livekit.io/) — 开源 WebRTC SFU（语音通话）
- [SRS](https://ossrs.io/) — 高性能 RTMP/FLV 流媒体服务器
- [media_kit](https://github.com/media-kit/media-kit) — Flutter 跨平台媒体播放器
- [Flutter](https://flutter.dev/) — 跨平台 UI 框架
- [Gin](https://gin-gonic.com/) — Go Web 框架
- [WireGuard](https://www.wireguard.com/) — 现代 VPN 协议
