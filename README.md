# NexusRoom

> 专为小型私有圈子设计的自托管集成通讯平台

[![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)](https://github.com/StarDream2736/Nexusroom)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 功能特性

- **即时通讯 (IM)** — 房间内文字消息、图片发送、历史记录离线同步
- **多人语音** — LiveKit WebRTC 语音频道、自由开关麦、说话状态指示
- **RTMP 推流直播** — SRS 6 接收 OBS 推流，HTTP-FLV 分发，media_kit 播放
- **虚拟局域网 (VLAN)** — 内嵌 WireGuard，一键组建局域网联机
- **Web 管理后台** — 超管面板、用户管理、房间管理
- **好友系统** — 通过数字 ID 添加好友，邀请进房间

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    【 客户端层 Client Layer 】               │
│              Flutter Desktop App (Windows / macOS)          │
│    UI · WebSocket Client · LiveKit SDK · media_kit · WG-go  │
│                      SQLite 本地缓存                         │
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
# 1. 克隆仓库并进入部署目录
git clone https://github.com/StarDream2736/Nexusroom.git
cd Nexusroom/deploy

# 2. 运行一键部署脚本（自动生成配置、拉取镜像、启动服务）
chmod +x deploy.sh
./deploy.sh

# 3. 配置防火墙（按需开放端口）
sudo ufw allow 8080/tcp          # API 服务
sudo ufw allow 1935/tcp          # SRS RTMP 推流
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
| 1935 | TCP | SRS 6 | RTMP 推流接收（OBS） |
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
├── server/        # Go 后端（Gin + GORM + WebSocket）
├── client/        # Flutter Desktop 客户端
├── deploy/        # Docker Compose & 配置模板
└── docs/          # 技术文档
```

## 开发路线图

- [x] 第一阶段：基础设施 + IM
- [x] 第二阶段：音视频集成（LiveKit 语音 + SRS 推流）
- [ ] 第三阶段：管理功能与扩展接口
- [ ] 第四阶段：VLAN 与屏幕共享

## 许可证

MIT License

## 致谢

- [LiveKit](https://livekit.io/) — 开源 WebRTC SFU（语音通话）
- [SRS](https://ossrs.io/) — 高性能 RTMP/FLV 流媒体服务器
- [media_kit](https://github.com/media-kit/media-kit) — Flutter 跨平台媒体播放器
- [Flutter](https://flutter.dev/) — 跨平台 UI 框架
- [Gin](https://gin-gonic.com/) — Go Web 框架
- [WireGuard](https://www.wireguard.com/) — 现代 VPN 协议
