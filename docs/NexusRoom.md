# NexusRoom 技术文档

本文描述 NexusRoom `2.0.0` 单体架构的当前实现。本地开发日志位于被 Git 忽略的 `docs/development/`，归档日志位于 `docx/`。

## 1. 架构目标

NexusRoom 服务端是一个可独立构建和部署的 Go 程序。业务需要的媒体能力已经成为项目内部模块，不再通过 Docker 编排外部数据库、缓存、SFU 或流媒体服务。

```text
Flutter 客户端 / 浏览器 / OBS
              |
              | HTTP, WebSocket, WebRTC, RTMP, WireGuard
              v
+-----------------------------------------------------------+
|                 NexusRoom 单一进程                         |
| API | WS 信令 | SQLite | 语音 SFU | RTMP | FLV | RTC 播放 |
| TURN | WireGuard 协调 | 内嵌网页                           |
+-----------------------------------------------------------+
              |
              v
       SQLite 文件与上传文件目录
```

开源项目的源码和协议实现用于参考或作为编译期依赖。NexusRoom 不启动 LiveKit Server、SRS、PostgreSQL、Redis 或 nginx，也不把这些程序作为隐藏的子进程运行。

## 2. 组件职责

| 模块 | 路径 | 职责 |
| --- | --- | --- |
| 进程装配 | `server/cmd/server` | 配置、模块初始化、监听端口和优雅关闭 |
| 数据库 | `server/internal/database` | SQLite、WAL、迁移、完整性检查 |
| 应用信令 | `server/internal/ws` | 房间事件、聊天、媒体 SDP/ICE 信令 |
| 语音 SFU | `server/internal/media/voice` | Opus 上行接收、房间转发、参与者状态 |
| RTMP 接入 | `server/internal/media/rtmp` | `/live/{streamKey}` 发布鉴权和 H.264 读取 |
| 流注册表 | `server/internal/media/stream` | 活跃流、订阅者、关键帧和统计 |
| FLV 封装 | `server/internal/media/flv` | H.264 到 HTTP-FLV 的低延迟封装 |
| RTC 播放 | `server/internal/media/rtcplay` | H.264 到浏览器 WebRTC 的 SDP 协商与发送 |
| TURN | `server/internal/media/turnserver` | STUN/TURN UDP 中继和长期凭据认证 |
| 网页 | `server/web` | 编译进二进制的房间列表与播放器 |

## 3. 数据层

服务端使用 SQLite，不执行旧数据库的数据迁移。首次启动通过 GORM 创建当前表结构。

默认数据库参数：

- WAL 日志模式。
- 5 秒 busy timeout。
- 启用外键约束。
- 启动时运行完整性与外键检查。
- 消息扩展字段以 SQLite `TEXT` 保存 JSON。

需要备份的内容只有数据库文件和上传目录。Docker 默认位于 `deployment/data/`；直接部署默认位于 `/var/lib/nexusroom/`。

## 4. 语音流程

1. 客户端加入房间后创建本地麦克风 Opus 轨道，默认静音。
2. SDP Offer、Answer 和 ICE Candidate 通过已认证的应用 WebSocket 传输。
3. 服务端为房间维护 PeerConnection 和参与者轨道。
4. 任一参与者的 Opus RTP 被转发给房间内其他 PeerConnection。
5. 开关麦和说话状态通过房间事件广播。
6. 断线、离房或连接失败会清理 PeerConnection 与转发轨道。
7. 客户端预留多人音频接收轨道，服务端对连续重协商进行排队，并且只转发未静音参与者的 RTP。

客户端不再请求媒体 Token，也不连接独立 SFU 地址。服务器在 WebSocket `connected` 事件中下发 ICE/TURN 配置。

## 5. 直播流程

推流地址格式：

```text
rtmp://SERVER:1935/live/STREAM_KEY
```

当前直播链路：

```text
OBS / FFmpeg
  -> NexusRoom RTMP 接入
  -> H.264 活跃流注册表
     -> HTTP-FLV -> Flutter media_kit 或浏览器回退
     -> WebRTC H.264 -> 纯视频流的浏览器优先播放
```

Stream Key 必须存在于 `room_ingresses` 表，正在使用的 key 不允许重复发布。推流开始和结束直接更新入口状态并广播房间事件，不再依赖 HTTP 回调。

当前 RTMP 内建链路处理 H.264 视频和可选 AAC 音频。桌面客户端通过 HTTP-FLV 播放两条轨道；浏览器对纯视频流优先使用 WebRTC，对含 AAC 的流主动回退 HTTP-FLV，以避免无转码条件下丢失音频。客户端屏幕捕获仍是纯视频路径。

公开播放接口：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/stream/:streamKey` | NexusRoom 直接输出 HTTP-FLV |
| GET | `/api/v1/web/rooms/live` | 从内部流注册表列出活跃直播 |
| POST | `/api/v1/web/rtc/play` | 直接完成浏览器 WebRTC 播放协商 |

## 6. TURN 与网络

内建 TURN 使用独立的 UDP 中继端口范围，避免与 WebRTC 直连端口争用。必须配置公网 IP、用户名和密码。客户端优先尝试直连 ICE，必要时使用 TURN 中继。

| 端口 | 协议 | 模块 |
| --- | --- | --- |
| 8080 | TCP | API、WebSocket、网页、HTTP-FLV |
| 1935 | TCP | RTMP 接入 |
| 3478 | UDP | STUN/TURN 监听 |
| 50000-50050 | UDP | WebRTC 直连媒体 |
| 51000-51100 | UDP | TURN 中继 |
| 51820 | UDP | WireGuard |

生产环境应使用 TLS 反向入口保护 HTTP 和 WebSocket。浏览器麦克风与部分 WebRTC 能力要求 HTTPS 或 localhost。当前单体目标表示只部署一个 NexusRoom 应用进程，并不禁止基础设施层在应用外终止 TLS。

## 7. 配置

```yaml
server:
  port: 8080
  mode: release
  domain: "example.com"

database:
  path: "/var/lib/nexusroom/nexusroom.db"

media:
  public_ip: "203.0.113.10"
  rtc:
    udp_port_min: 50000
    udp_port_max: 50050
  rtmp:
    port: 1935
  turn:
    enabled: true
    port: 3478
    realm: nexusroom
    username: "replace-me"
    password: "replace-me"
    relay_port_min: 51000
    relay_port_max: 51100
```

完整模板位于 `deployment/templates/server.yaml.template`。配置中包含敏感凭据，不应提交到 Git。

## 8. 部署

Docker 方案只构建并运行一个 `nexusroom` 容器。SQLite 和上传文件通过一个数据目录持久化。

直接部署方案构建同一份源码，安装同一个二进制，并通过 `nexusroom.service` 管理。两种方案使用相同配置结构和端口模型。

具体命令见 `deployment/README.md`。

## 9. 客户端兼容与 UI 约定

Flutter 客户端用 `flutter_webrtc` 连接内建语音 SFU，直播播放器仍保留既有 `media_kit` 路径。业务模型中的 `livekit_room_name` 已替换为中性的 `media_room_name`。

本次改造不调整 UI 布局、颜色、组件尺寸和交互。在线、离线、说话状态所使用的圆点和 emoji 属于界面语义，继续保留。日志、脚本、README 和维护文档不使用 emoji。

## 10. 开源依赖与维护边界

- Pion WebRTC：ICE、DTLS、SRTP、RTP 和 PeerConnection 协议实现。
- Pion TURN：STUN/TURN 协议实现。
- gortmplib：RTMP 协议解析；当前固定版本，升级时必须运行推流回归测试。
- flutter_webrtc：Flutter 平台 WebRTC 绑定。
- GORM 与 go-sqlite3：嵌入式数据库访问。

上述组件被编译进 NexusRoom 或客户端，是源代码依赖，不拥有独立业务状态、房间模型或部署生命周期。

## 11. 验证基线

```bash
cd server
go test ./...

cd ../client
flutter analyze
flutter test

cd ../deployment
docker compose config --quiet
```

媒体上线前还应执行两客户端语音互通、OBS 推流、Flutter FLV 播放、浏览器 WebRTC 播放、TURN 强制中继和进程重启后的 SQLite 持久化检查。

当前自动验证已覆盖 Go 测试与 vet、SQLite、聊天持久化与发送关联 ID、真实 PeerConnection 的 Opus RTP 转发、FLV、流注册、真实 PeerConnection 的 H.264 RTP、WireGuard 私钥持久化、Flutter analyze/test、WebSocket 房间与消息确认、Compose 配置和单体进程 `/ping` 启动探针。跨公网媒体互通仍必须在真实部署网络中验收。

## 12. 2026-07-15 变更摘要

- 仓库拆分为客户端、服务端、部署和文档四个维护区域。
- 服务端从 PostgreSQL 改为 SQLite，不迁移历史数据。
- 移除 Redis 连接和缓存依赖。
- 语音从独立 LiveKit Server 改为 NexusRoom 内建 Opus SFU。
- 直播从独立 SRS 改为内建 RTMP、流注册、FLV 和 WebRTC 播放模块。
- 内建 TURN 并通过应用 WebSocket下发 ICE 配置。
- 网页资源编译进 Go 二进制，移除 nginx 容器。
- Docker Compose 收敛为一个容器，并新增直接 Linux/systemd 部署。
- 保留既有 UI 及其状态 emoji，移除非 UI 内容中的 emoji。
