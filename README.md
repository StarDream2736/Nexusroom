# NexusRoom

> 专为小型私有圈子设计的自托管集成通讯平台

[![Version](https://img.shields.io/badge/version-1.3.1-blue.svg)](https://github.com/yourusername/nexusroom)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 功能特性

- **即时通讯 (IM)** - 房间内文字消息、图片发送、历史记录同步
- **多人语音** - WebRTC 语音频道、自由开关麦
- **RTMP 推流直播** - 接受 OBS 等第三方软件推流、多路流管理
- **虚拟局域网 (VLAN)** - 内嵌 WireGuard，一键组建局域网联机
- **Web 管理后台** - 超管面板、用户管理、房间管理
- **好友系统** - 通过用户 ID 添加好友，邀请进房间

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    【 客户端层 Client Layer 】               │
│              Flutter Desktop App (Windows / macOS)          │
│       UI · WebSocket Client · LiveKit SDK · WireGuard-go    │
│                      SQLite 本地缓存                         │
└──────────────────────┬──────────────────────────────────────┘
                       │  HTTPS / WSS / WebRTC  (OBS→Ingress: RTMP)
┌──────────────────────▼──────────────────────────────────────┐
│                    【 服务端层 Server Layer 】               │
│                                                             │
│   Golang Main Server    LiveKit Server    LiveKit Ingress   │
│   REST API · WebSocket  SFU · 语音/视频   RTMP→WebRTC 转码   │
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
# 1. 进入部署目录
cd deploy

# 2. 运行部署脚本
chmod +x deploy.sh
./deploy.sh

# 3. 配置防火墙
sudo ufw allow 8080/tcp
sudo ufw allow 1935/tcp
sudo ufw allow 7880/tcp
sudo ufw allow 50000:50050/udp
sudo ufw allow 51820/udp
```

详细部署文档：[DEPLOY.md](docs/DEPLOY.md)

### 客户端编译

```bash
# 1. 进入客户端目录
cd client

# 2. 安装依赖
flutter pub get

# 3. 运行调试版本
flutter run -d windows  # 或 macos / linux

# 4. 编译发布版本
flutter build windows --release
```

详细编译文档：[BUILD_CLIENT.md](docs/BUILD_CLIENT.md)

## 文档

- [服务端编译文档](docs/BUILD_SERVER.md) - 服务端编译和开发指南
- [客户端编译文档](docs/BUILD_CLIENT.md) - 客户端编译和开发指南
- [部署文档](docs/DEPLOY.md) - 生产环境部署指南
- [技术规范](NexusRoom.md) - 完整的技术实现规范

## 端口说明

| 端口 | 协议 | 服务 | 说明 |
|------|------|------|------|
| 8080 | TCP | Golang 主服务 | REST API + WebSocket |
| 1935 | TCP | LiveKit Ingress | RTMP 推流接收（OBS） |
| 7880 | TCP | LiveKit | WebRTC 信令 |
| 50000-50050 | UDP | LiveKit | WebRTC 媒体流 |
| 51820 | UDP | WireGuard | VLAN 虚拟局域网 |
| 3000 | TCP | Web 管理后台 | 可选，仅管理员访问 |

## 系统要求

### 服务端

- Docker 20.10+
- Docker Compose 2.0+
- 2核 CPU / 4GB 内存（小型部署）

### 客户端

- Windows 10+ / macOS 11+ / Linux
- Flutter 3.x

## 开发路线图

- [x] 第一阶段：基础设施 + IM
- [x] 第二阶段：音视频集成
- [ ] 第三阶段：管理功能与扩展接口
- [ ] 第四阶段：VLAN 与屏幕共享

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 致谢

- [LiveKit](https://livekit.io/) - 开源 WebRTC SFU
- [Flutter](https://flutter.dev/) - 跨平台 UI 框架
- [Gin](https://gin-gonic.com/) - Go Web 框架
- [WireGuard](https://www.wireguard.com/) - 现代 VPN 协议
