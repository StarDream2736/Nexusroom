# NexusRoom 技术实现规划 & 开发文档

> **版本** v1.3.3 ｜ **定位** 私有化部署 · 自建服务端 ｜ **核心功能** IM · 语音 · 直播 · VLAN

## 变更日志

| 版本     | 变更内容                                                                                                                                                                                                                                         |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| v1.3.4 | **\[LiveKit连接修复]** 服务端GetDetail端点添加智能URL推导（优先使用config.public_url，自动从Host头识别公网IP），livekit.yaml改用node_ip替代use_external_ip避免外网查询超时；**\[头像稳定性]** 修复客户端avatar组件因空字符串导致的CachedNetworkImageProvider崩溃；**\[实时功能]** 新增speakingUsersProvider和onlineUsersProvider(WS事件+REST fallback)，成员列表支持在线/说话状态指示和排序；**\[自动刷新]** 房间详情3s周期刷新、直播列表10s周期刷新；**\[权限调整]** Ingress推流入口权限从房主限制改为房间全体成员可操作 |
| v1.3.3 | **\[Bug修复]** 修复登录页"切换服务器"按钮（clearAuth改为clearAll避免状态残留）；**\[架构优化]** AppShell重构为StatefulWidget，集中处理房间join/leave逻辑，修复GoRouterState上下文错误导致的房间切换失效；**\[稳定性]** 新增WebSocket重连后自动重新加入已加入房间机制（_joinedRooms追踪 + connected事件触发 + chat.error兜底）；**\[诊断]** 全面补充客户端与服务端消息链路诊断日志 |
| v1.3.2 | **\[实现修订]** WebSocket Hub 初始化新增 userRepo 参数用于获取用户昵称；补充客户端时间戳必须使用 UTC 的实现细节；明确客户端本地数据库存储路径（Documents/nexusroom.sqlite）；补充 Docker Compose 环境变量配置说明（.env 文件）；修复客户端路由导航逻辑避免 widget 销毁后导航失败 |
| v1.3.1 | **\[审校修复]** 成功响应码统一为 20000；补充遗漏的 livekit-token 接口；标注 stream.new 等 SRS 遗留事件为废弃；room_code 字段说明更新；修复 Simulcast 代码中 setScreenShareEnabled 与手动 publish 的逻辑冲突；及 Roadmap 验收标准去除硬编码网段；修复 isFocused() 缺失 await；补充 HTTP/HTTPS 启用条件说明；推流密钥安全规范更新；章节编号修正 |
| v1.3.0 | **\[新增]** 后台挂起资源管理：窗口最小化/失焦时自动暂停所有视频轨道解码，恢复时重新唤醒，为游戏玩家保留 GPU/CPU 资源；**\[新增]** 视频流分辨率控制：屏幕共享启用 Simulcast 实现侧边栏 Low/主视窗 High 动态切换，OBS Ingress 推流采用"延迟订阅"折中方案（侧边栏仅显示封面，点击后订阅）                                                                   |
| v1.2.0 | **[架构]** 以 LiveKit Ingress 完全替代 SRS，RTMP 推流统一进入 LiveKit 生态，客户端去除 media_kit 等传统播放器，全部使用 LiveKit SDK 渲染，直播延迟降至 200ms 以内；**[修订]** VLAN 子网段改为可配置，新增冲突风险说明及 Web 后台变更警告                                                                            |
| v1.1.0 | **[修订]** 新增 5.7 文件模块，补全图片/文件上传的两步闭环流程；**[修订]** 消息增量同步锚点由 `created_at` 改为自增主键 `id`，修复高并发漏消息隐患；**[修订]** LiveKit UDP 端口范围从 50000-50200 缩小至 50000-50050，补充与 livekit.yaml 必须同步的说明                                                                 |
| v1.0.0 | 初始版本                                                                                                                                                                                                                                         |

---

## 目录

- [第一章 项目概述](#第一章-项目概述)
- [第二章 系统架构设计](#第二章-系统架构设计)
- [第三章 目录结构规范](#第三章-目录结构规范)
- [第四章 数据模型设计](#第四章-数据模型设计)
- [第五章 API 接口设计](#第五章-api-接口设计)
- [第六章 音视频模块实现](#第六章-音视频模块实现)
- [第七章 VLAN 虚拟局域网实现](#第七章-vlan-虚拟局域网实现)
- [第八章 客户端架构详解](#第八章-客户端架构详解)
- [第九章 服务端配置与部署](#第九章-服务端配置与部署)
- [第十章 开发路线图](#第十章-开发路线图)
- [第十一章 开发规范](#第十一章-开发规范)
- [附录](#附录)

---

# 第一章 项目概述

## 1. 项目定位与目标

NexusRoom 是一款专为小型私有圈子（游戏群体、技术团队、私密社交）设计的自托管集成通讯平台。所有数据由部署者完全掌控，不依赖任何第三方云服务。

### 1.1 核心设计原则

- **私有化优先**：Server/Client 完全分离，用户通过填写服务端 IP 绑定自己的实例
- **高集成度**：IM 即时通讯 + 多人语音 + 多路直播推流 + 虚拟局域网，一个软件全部覆盖
- **可扩展性**：预留 QQ 机器人 Webhook 接口、Android/iOS 移动端接口，模块化设计便于后续扩展
- **最小化依赖**：用户端无需安装任何第三方软件即可使用包含 VLAN 在内的全部功能

### 1.2 功能全景

| 模块 | 功能描述 | 优先级 | 开发阶段 |
|------|---------|--------|---------|
| 即时通讯 (IM) | 房间内文字消息、图片发送、历史记录同步 | P0 | 第一阶段 |
| 用户系统 | 注册/登录、头像昵称、数字ID、好友系统 | P0 | 第一阶段 |
| 房间管理 | 创建/加入/踢出、邀请码、管理员权限 | P0 | 第一阶段 |
| 多人语音 | WebRTC 语音频道、自由开关麦 | P1 | 第二阶段 |
| RTMP 推流直播 | 接受 OBS 等第三方软件推流、多路流管理 | P1 | 第二阶段 |
| Web 管理后台 | 超管面板、用户管理、房间管理、配置调整 | P1 | 第三阶段 |
| QQ 机器人接口 | OneBot 兼容 Webhook，消息推送到房间 | P2 | 第三阶段 |
| 好友邀请 | 通过用户 ID 添加好友，邀请进房间 | P2 | 第三阶段 |
| VLAN 虚拟局域网 | 内嵌 WireGuard，一键组建局域网联机 | P2 | 第四阶段 |
| 屏幕共享 | 客户端屏幕采集，通过 WebRTC 推流 | P3 | 第四阶段 |

---

# 第二章 系统架构设计

## 2. 整体架构

系统采用三层分离架构：前端客户端（Flutter Desktop）、后端主服务（Golang）、音视频引擎（LiveKit + LiveKit Ingress）。客户端通过 WebSocket 连接服务端，所有音视频流（语音、OBS 推流、屏幕共享）统一通过 LiveKit WebRTC 通道传输，不再依赖 SRS 等独立媒体服务器。

### 2.1 架构总览图

> 所有服务端组件均运行在同一台服务器上，通过 Docker Compose 编排。

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

### 2.2 技术栈选型

| 层级       | 技术                      | 版本建议       | 选型理由                                                  |
| -------- | ----------------------- | ---------- | ----------------------------------------------------- |
| 客户端      | Flutter Desktop         | 3.x Stable | 一套代码，未来可适配 Android/iOS                                |
| 客户端状态管理  | Riverpod                | 2.x        | 类型安全，适合复杂状态场景                                         |
| 客户端本地存储  | SQLite (drift)          | 最新稳定版      | 离线消息缓存，增量同步                                           |
| 后端主服务    | Golang                  | 1.22+      | 高并发，原生支持 WireGuard 生态库                                |
| 后端框架     | Gin + gorilla/websocket | 最新稳定版      | 轻量，性能优秀                                               |
| 音视频引擎    | LiveKit                 | 1.x        | 开源 SFU，支持 WebRTC，有 Flutter SDK                        |
| 推流接收     | LiveKit Ingress         | 1.x        | LiveKit 官方 RTMP 接入组件，将推流直接转码为 WebRTC Track，与语音/视频统一渲染 |
| 数据库      | PostgreSQL              | 16.x       | 稳定，适合消息存储                                             |
| 缓存/会话    | Redis                   | 7.x        | 在线状态、房间状态、WebSocket 会话管理                              |
| VLAN     | wireguard-go + wintun   | 最新稳定版      | 纯 Go 实现，可打包进安装包，用户无感知                                 |
| Web 管理后台 | Vue 3 + Ant Design Vue  | 最新稳定版      | 独立前端，共用后端 REST API                                    |
| 容器化部署    | Docker + Docker Compose | 最新稳定版      | 一键启动所有服务端组件                                           |

---

# 第三章 目录结构规范

### 3.1 Monorepo 整体结构

```
nexusroom/
├── server/                    # Golang 后端主服务
├── client/                    # Flutter 桌面客户端
├── web-admin/                 # Vue 3 Web 管理后台
├── deploy/                    # Docker Compose & 配置模板
├── docs/                      # 文档
└── scripts/                   # 构建 & 部署脚本
```

### 3.2 服务端目录结构

```
server/
├── cmd/
│   └── server/
│       └── main.go            # 程序入口
├── internal/
│   ├── api/                   # HTTP REST API 路由
│   │   ├── handler/           # 各业务 Handler
│   │   ├── middleware/        # Auth / CORS / RateLimit
│   │   └── router.go          # 路由注册
│   ├── ws/                    # WebSocket 处理
│   │   ├── hub.go             # 连接中心 (Hub)，初始化需要三个参数：NewHub(msgRepo, roomRepo, userRepo)
│   │   ├── client.go          # 单个客户端连接
│   │   └── message.go         # 消息类型定义
│   ├── model/                 # 数据库模型 (GORM)
│   ├── service/               # 业务逻辑层
│   ├── repository/            # 数据访问层
│   ├── wg/                    # WireGuard 协调服务
│   │   ├── coordinator.go     # 密钥分发 & IP 分配
│   │   └── peer.go            # Peer 状态管理
│   └── config/
│       └── config.go          # 配置加载
├── pkg/                       # 可复用公共包
│   ├── jwt/                   # JWT 工具
│   └── util/
├── migrations/                # 数据库迁移文件
└── config.yaml                # 服务端配置文件
```

### 3.3 客户端目录结构

```
client/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── router/            # GoRouter 路由配置（app_router.dart）
│   │   ├── shell/             # AppShell（集中房间join/leave逻辑）、Sidebar、RightPanel
│   │   ├── theme/             # 全局主题（app_theme.dart、app_colors.dart）
│   │   └── widgets/           # 通用UI组件（title_bar.dart、glass_container.dart等）
│   ├── features/              # 按功能模块分层
│   │   ├── auth/              # 登录/注册/服务器绑定
│   │   │   └── presentation/  # UI 页面（login_page.dart、setup_page.dart）
│   │   │       └── providers/ # Riverpod状态管理（auth_controller.dart）
│   │   ├── room/              # 房间模块（包含聊天、语音、直播流管理）
│   │   │   └── presentation/  # UI 页面与状态管理
│   │   │       ├── pages/     # room_list_page、room_detail_page、room_settings_page等
│   │   │       ├── providers/ # rooms_provider、messages_provider、voice_state_provider等
│   │   │       └── widgets/   # 房间相关UI组件
│   │   ├── user/              # 用户/好友
│   │   │   └── presentation/  # friends_page.dart
│   │   └── vlan/              # 虚拟局域网
│   │       └── presentation/  # vlan_panel.dart
│   ├── core/                  # 核心基础设施层
│   │   ├── db/                # SQLite (drift) 本地数据库
│   │   │   ├── app_database.dart
│   │   │   ├── tables/        # 数据表定义（messages.dart、settings.dart）
│   │   │   └── daos/          # 数据访问对象（messages_dao.dart、settings_dao.dart）
│   │   ├── models/            # 数据模型（auth_models、room_models、message_models等）
│   │   ├── network/           # 网络层
│   │   │   ├── api_client.dart      # HTTP客户端（Dio）
│   │   │   ├── ws_service.dart      # WebSocket服务（含重连、_joinedRooms追踪）
│   │   │   ├── livekit_service.dart # LiveKit音视频服务
│   │   │   └── stream_player.dart   # 流播放器
│   │   ├── native/            # Platform Channel（wireguard_service.dart）
│   │   ├── providers/         # 全局Riverpod Providers（app_providers.dart）
│   │   ├── repositories/      # 数据仓库层（settings_repository、file_repository）
│   │   ├── state/             # 全局状态管理（app_settings_controller.dart）
│   │   └── window/            # 窗口生命周期管理（window_lifecycle_service.dart）
├── assets/
│   ├── icons/
│   └── images/
├── test/
└── pubspec.yaml
```

> **实现说明**：实际代码中 chat、voice、stream 模块已整合到 room 模块内，通过 providers 和 widgets 划分职责。这种结构更符合小型项目的简洁性原则。

---

# 第四章 数据模型设计

## 4. 数据库模型

服务端使用 PostgreSQL 作为主数据库。

### 4.1 用户表 (users)

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| id | BIGSERIAL | PRIMARY KEY | 系统内部自增主键 |
| user_display_id | VARCHAR(12) | UNIQUE NOT NULL | 用户可见的数字 ID，6-12位随机数字 |
| username | VARCHAR(64) | UNIQUE NOT NULL | 登录用户名 |
| password_hash | VARCHAR(255) | NOT NULL | bcrypt 哈希密码 |
| nickname | VARCHAR(64) | NOT NULL | 显示昵称，可重复 |
| avatar_url | VARCHAR(512) | NULL | 头像图片 URL，存储相对路径 |
| role | VARCHAR(16) | NOT NULL DEFAULT 'user' | 角色：user / super_admin |
| is_active | BOOLEAN | NOT NULL DEFAULT true | 账户是否启用 |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | 注册时间 |
| last_login_at | TIMESTAMPTZ | NULL | 最后登录时间 |

### 4.2 房间表 (rooms)

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| id | BIGSERIAL | PRIMARY KEY | |
| room_code | VARCHAR(16) | UNIQUE NOT NULL | 房间内部唯一标识，用于生成 LiveKit room_name 等内部用途（Ingress 推流地址由 LiveKit API 统一生成，不再使用 room_code 拼接） |
| invite_code | VARCHAR(8) | UNIQUE NOT NULL | 6位邀请码，用户可见 |
| name | VARCHAR(128) | NOT NULL | 房间名称 |
| owner_id | BIGINT | FK → users.id | 创建者用户ID |
| livekit_room_name | VARCHAR(128) | UNIQUE NOT NULL | LiveKit 内部房间名 |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

### 4.3 房间成员表 (room_members)

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| room_id | BIGINT | FK → rooms.id | |
| user_id | BIGINT | FK → users.id | |
| role | VARCHAR(16) | NOT NULL DEFAULT 'member' | member / admin |
| joined_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| | PRIMARY KEY | (room_id, user_id) | 联合主键 |

### 4.4 消息表 (messages)

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| id | BIGSERIAL | PRIMARY KEY | |
| room_id | BIGINT | FK → rooms.id NOT NULL | 所属房间 |
| sender_id | BIGINT | FK → users.id NOT NULL | 发送者 |
| type | VARCHAR(16) | NOT NULL | text / image / system |
| content | TEXT | NOT NULL | 文本内容，image/file 类型存文件 URL |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | 发送时间，用于消息清理（不作为同步锚点） |

> 服务端定时任务（cron）根据 `config.yaml` 中配置的 `message_retention_days` 自动清理过期消息。**增量同步锚点使用自增主键 `id` 而非 `created_at`**，可彻底规避时钟漂移、高并发同一时间戳导致的漏消息问题。

### 4.5 推流 Ingress 表 (room_ingresses)

使用 LiveKit Ingress 后，推流密钥由 LiveKit Ingress API 统一管理。主服务在创建房间时调用 Ingress API 创建一个 RTMP Ingress 对象，并将返回的 `ingress_id`、推流 URL 和 Stream Key 存储在本表中供客户端查询。

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| id | BIGSERIAL | PRIMARY KEY | |
| room_id | BIGINT | FK → rooms.id NOT NULL | 所属房间 |
| ingress_id | VARCHAR(128) | UNIQUE NOT NULL | LiveKit Ingress API 返回的 ID |
| stream_key | VARCHAR(128) | UNIQUE NOT NULL | OBS 填写的推流密钥（由 Ingress API 生成） |
| rtmp_url | VARCHAR(256) | NOT NULL | OBS 填写的推流服务器地址（由 Ingress API 生成） |
| label | VARCHAR(64) | NULL | 密钥备注，如 'OBS主推流' |
| is_active | BOOLEAN | NOT NULL DEFAULT true | 是否启用 |
| created_by | BIGINT | FK → users.id | 创建者（房主） |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

> 每个房间可创建多个 Ingress（对应多路推流），每个 Ingress 在 LiveKit Room 内表现为一个独立的 Participant Track，客户端使用统一的 LiveKit SDK 订阅，无需引入额外播放器。

### 4.6 好友关系表 (friendships)

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| requester_id | BIGINT | FK → users.id | 发起添加的用户 |
| addressee_id | BIGINT | FK → users.id | 被添加的用户 |
| status | VARCHAR(16) | NOT NULL DEFAULT 'pending' | pending / accepted / rejected |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| | PRIMARY KEY | (requester_id, addressee_id) | 联合主键 |

### 4.7 VLAN Peer 表 (wg_peers)

| 字段名 | 类型 | 约束 | 说明 |
|-------|------|------|------|
| id | BIGSERIAL | PRIMARY KEY | |
| room_id | BIGINT | FK → rooms.id NOT NULL | 所属房间 |
| user_id | BIGINT | FK → users.id NOT NULL | |
| public_key | VARCHAR(64) | NOT NULL | WireGuard 客户端公钥 |
| assigned_ip | VARCHAR(18) | NOT NULL | 分配的虚拟 IP，如 10.0.8.5/24 |
| last_handshake_at | TIMESTAMPTZ | NULL | 最后握手时间 |

---

# 第五章 API 接口设计

## 5. REST API 规范

### 5.1 通用规范

- **Base URL**：`http(s)://{server_ip}:{port}/api/v1`（未配置域名时使用 `http`；在 config.yaml 中配置 `server.domain` 后服务自动启用 TLS，客户端改用 `https`）
- **认证方式**：Bearer Token（JWT），在 `Authorization` 请求头中携带
- **内容类型**：`Content-Type: application/json`
- **时间格式**：统一使用 RFC3339 格式（`2024-01-01T12:00:00Z`）
  - **客户端实现要求**：发送时间戳时必须使用 UTC 时区，Dart/Flutter 中应调用 `DateTime.now().toUtc().toIso8601String()` 确保时区信息完整
- **分页参数**：`page`（从 1 开始）、`page_size`（默认 50，最大 100）

### 5.2 统一响应格式

```json
// 成功响应
{
  "code": 20000,
  "message": "ok",
  "data": { }
}

// 错误响应
{
  "code": 40001,
  "message": "用户名已存在",
  "data": null
}
```

### 5.3 错误码表

| 错误码 | HTTP状态码 | 说明 |
|-------|-----------|------|
| 20000 | 200 | 成功 |
| 40001 | 400 | 参数校验失败 |
| 40101 | 401 | 未登录或 Token 过期 |
| 40301 | 403 | 权限不足（非房主操作） |
| 40302 | 403 | 超管令牌错误 |
| 40401 | 404 | 资源不存在 |
| 40901 | 409 | 用户名/邀请码冲突 |
| 50001 | 500 | 服务内部错误 |

### 5.4 认证模块

#### POST /auth/register — 用户注册

```json
// Request Body
{
  "username": "alice",
  "password": "SecurePass123!",
  "nickname": "Alice",
  "admin_token": ""      // 可选，填入超管令牌则注册为超级管理员
}

// Response
{
  "data": {
    "user_id": 1001,
    "user_display_id": "483921",
    "token": "eyJhbGci..."
  }
}
```

#### POST /auth/login — 用户登录

```json
// Request Body
{ "username": "alice", "password": "SecurePass123!" }

// Response: 同 register，返回新 token
```

### 5.5 房间模块

| 方法 | 路径 | 权限 | 说明 |
|------|------|------|------|
| POST | /rooms | 已登录 | 创建房间，自动生成邀请码 |
| POST | /rooms/join | 已登录 | 通过邀请码加入房间 |
| GET | /rooms/:roomId | 房间成员 | 获取房间详情（成员列表、推流地址） |
| PATCH | /rooms/:roomId | 房主/超管 | 修改房间名称 |
| DELETE | /rooms/:roomId/members/:userId | 房主/超管 | 踢出成员 |
| POST | /rooms/:roomId/ingresses | 房主 | 调用 LiveKit Ingress API 创建新推流入口，返回 rtmp_url 和 stream_key |
| GET | /rooms/:roomId/ingresses | 房主 | 获取本房间所有推流入口（含推流地址和密钥） |
| DELETE | /rooms/:roomId/ingresses/:ingressId | 房主 | 删除推流入口（同步调用 Ingress API 删除） |
| POST | /rooms/:roomId/livekit-token | 房间成员 | 生成 LiveKit Access Token，客户端凭此 Token 直接连接 LiveKit Server |
| GET | /rooms/:roomId/messages | 房间成员 | 拉取历史消息，使用 `after_id` 向后分页（增量同步）或 `before_id` 向前分页（加载更早消息） |

#### POST /rooms — 创建房间（详细）

```json
// Request Body
{ "name": "我的游戏房间" }

// Response
{
  "data": {
    "id": 5,
    "name": "我的游戏房间",
    "room_code": "rm_a3f9b2",
    "invite_code": "XK9P2M",
    "ingresses": [
      {
        "id": 1,
        "ingress_id": "INxxxxxxxxxxxx",
        "rtmp_url": "rtmp://your-server-ip:1935/x/live",
        "stream_key": "rm_a3f9b2_sk_xxxxx",
        "label": "默认推流入口"
      }
    ]
  }
}
```

### 5.6 用户模块

| 方法 | 路径 | 权限 | 说明 |
|------|------|------|------|
| GET | /users/me | 已登录 | 获取当前用户信息 |
| PATCH | /users/me | 已登录 | 修改昵称/头像 |
| POST | /users/me/avatar | 已登录 | 上传头像（multipart/form-data） |
| GET | /users/search?display_id= | 已登录 | 通过 display_id 搜索用户 |
| POST | /friends/request | 已登录 | 发送好友申请 |
| PATCH | /friends/request/:requestId | 已登录 | 接受/拒绝好友申请 |
| GET | /friends | 已登录 | 获取好友列表 |

### 5.7 文件模块（图片/文件上传）

WebSocket 不适合传输大体积二进制数据（会阻塞同一连接上的其他消息，且无断点续传）。图片和文件的发送采用**两步闭环**：客户端先通过 HTTP 上传文件拿到 URL，再通过 WebSocket 发送携带该 URL 的消息。

| 方法 | 路径 | 权限 | 说明 |
|------|------|------|------|
| POST | /files/upload | 已登录 | 上传图片或文件，返回访问 URL |
| GET | /files/:fileId | 房间成员 | 访问已上传的文件（需持有效 token） |

#### POST /files/upload — 上传文件（详细）

```http
POST /api/v1/files/upload
Content-Type: multipart/form-data
Authorization: Bearer {token}

file=<binary>
room_id=5          # 关联房间，用于权限校验（只有房间成员可上传）
```

```json
// Response
{
  "data": {
    "file_id": "f_8a3c2b",
    "url": "https://your-server-ip:8080/api/v1/files/f_8a3c2b",
    "mime_type": "image/png",
    "size_bytes": 204800,
    "file_name": "screenshot.png"
  }
}
```

#### 上传后发送图片消息的完整流程

```
1. 用户在输入框选择图片
        ↓
2. 客户端 HTTP POST /files/upload 上传图片
        ↓
3. 服务端校验 MIME type、文件大小，存储并返回 { url, file_id, ... }
        ↓
4. 客户端通过 WebSocket 发送：
   {
     "event": "chat.send",
     "room_id": 5,
     "payload": {
       "type": "image",
       "content": "https://your-server-ip:8080/api/v1/files/f_8a3c2b",
       "meta": { "file_name": "screenshot.png", "size_bytes": 204800 }
     }
   }
        ↓
5. 服务端将消息存入数据库并广播 chat.message 事件给房间所有成员
        ↓
6. 其他客户端收到消息，渲染缩略图（懒加载，点击后才请求原图）
```

#### 服务端安全校验要点

- **MIME 校验**：读取文件头魔数（magic bytes）判断真实类型，不依赖扩展名
- **白名单**：`image/jpeg`、`image/png`、`image/gif`、`image/webp`、`application/pdf` 及常见文档格式
- **大小限制**：读取 `config.yaml` 中 `storage.max_file_size_mb`，超限直接返回 413
- **文件名随机化**：存储时使用 `{uuid}.{ext}`，防止路径遍历攻击
- **访问权限**：`GET /files/:fileId` 需要验证请求方是文件关联房间的成员

### 5.8 VLAN 模块

| 方法 | 路径 | 权限 | 说明 |
|------|------|------|------|
| POST | /rooms/:roomId/vlan/join | 房间成员 | 注册公钥，获取分配的虚拟 IP 及服务端配置 |
| DELETE | /rooms/:roomId/vlan/leave | 房间成员 | 离开 VLAN，释放 IP |
| GET | /rooms/:roomId/vlan/peers | 房间成员 | 获取当前房间所有在线 VLAN Peer 信息 |

#### POST /rooms/:roomId/vlan/join

```json
// Request Body
{ "public_key": "base64_encoded_wireguard_public_key" }

// Response
{
  "data": {
    "assigned_ip": "10.0.8.5/24",
    "server_public_key": "base64_server_public_key",
    "server_endpoint": "your-server-ip:51820",
    "dns": "10.0.8.1",
    "peers": [
      {
        "user_id": 1002,
        "nickname": "Bob",
        "public_key": "base64_bob_public_key",
        "allowed_ips": "10.0.8.6/32"
      }
    ]
  }
}
```

### 5.9 超管 API（需超管权限）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /admin/users | 用户列表，支持搜索和分页 |
| PATCH | /admin/users/:userId | 禁用/启用用户 |
| GET | /admin/rooms | 所有房间列表 |
| DELETE | /admin/rooms/:roomId | 强制解散房间 |
| GET | /admin/config | 获取当前服务器配置 |
| PATCH | /admin/config | 修改配置（消息保留天数等） |
| GET | /admin/stats | 服务器统计（在线人数、消息量等） |

---

## 6. WebSocket 协议

### 6.1 连接建立

```
wss://{server_ip}:{port}/ws?token={jwt_token}
```

连接成功后，服务端发送 `connected` 事件确认。客户端需在 30 秒内发送第一个 `heartbeat`，此后每 30 秒发送一次。

### 6.2 消息格式（统一 Envelope）

```json
{
  "event": "事件名",
  "room_id": 5,
  "payload": { },
  "timestamp": "2024-01-01T12:00:00Z"
}
```

> **重要**：`timestamp` 字段必须包含时区信息，推荐使用 UTC（以 `Z` 结尾）。客户端发送时必须调用 `.toUtc()` 转换为 UTC 时间再序列化，否则服务器解析会失败。

### 6.3 客户端 → 服务端 事件

| Event | Payload | 说明 |
|-------|---------|------|
| heartbeat | {} | 心跳保活，服务端回复 pong |
| room.join | { room_id } | 通知服务端加入某房间的 Socket 频道 |
| room.leave | { room_id } | 离开房间频道 |
| chat.send | { room_id, type, content, meta? } | 发送消息。type=text 时 content 为文本；type=image/file 时 content 为先调用 POST /files/upload 获得的文件 URL，meta 携带 file_name、size_bytes |
| voice.mute | { room_id, muted: bool } | 通知其他成员自己的静音状态 |
| stream.start_notify | { room_id, stream_id } | 已废弃（SRS 时代遗留）。LiveKit Ingress 方案下，推流状态由 LiveKit SDK 的 ParticipantConnected / Disconnected 事件直接感知，不再需要此自定义事件。保留字段定义仅供参考，实现时可移除 |
| stream.stop_notify | { room_id, stream_id } | 已废弃，同上 |
| vlan.peer_update | { room_id, action, peer_info } | VLAN Peer 加入/离开通知 |

### 6.4 服务端 → 客户端 事件

| Event | Payload | 说明 |
|-------|---------|------|
| connected | { user_id, server_version } | 连接成功确认 |
| pong | {} | 心跳回复 |
| chat.message | { id, room_id, sender_id, type, content, meta, created_at, sender: { id, nickname, avatar_url } } | 新消息推送 |
| chat.error | { room_id, reason } | 消息发送失败（如 `reason="not_in_room"` 表示用户未加入房间），客户端收到后自动重新加入并提示用户 |
| room.member_join | { user_id, nickname, avatar_url } | 成员加入房间 |
| room.member_leave | { user_id } | 成员离开或被踢出 |
| room.kicked | { reason } | 你被踢出（仅发给被踢成员） |
| voice.state_update | { user_id, muted, speaking } | 成员语音状态变更 |
| stream.new | { stream_id, streamer_user_id, rtc_track_id } | 已废弃（SRS 时代遗留）。LiveKit Ingress 方案下，客户端直接通过 LiveKit SDK 感知 Ingress Participant 加入/离开，无需主服务中转广播此事件 |
| stream.ended | { stream_id } | 已废弃，同上 |
| friend.request | { from_user_id, nickname } | 收到好友申请 |
| friend.accepted | { user_id, nickname } | 好友申请被接受 |

---

# 第六章 音视频模块实现

## 7. 语音频道实现（LiveKit）

### 7.1 LiveKit 集成架构

LiveKit 作为独立的 SFU 服务运行，通过 Docker 在服务端部署。主服务（Golang）作为 LiveKit 的管理端，负责为客户端生成 Access Token；客户端使用 LiveKit Flutter SDK 直接与 LiveKit 服务建立 WebRTC 连接。

### 7.2 服务端：生成 LiveKit Token

```go
// 当用户加入房间，主服务生成 LiveKit Access Token
// 使用 livekit-server-sdk-go
func GenerateLiveKitToken(roomName, userID, nickname string) (string, error) {
    at := auth.NewAccessToken(livekitAPIKey, livekitAPISecret)
    grant := &auth.VideoGrant{
        RoomJoin:     true,
        Room:         roomName,
        CanPublish:   boolPtr(true),   // 可发布音视频
        CanSubscribe: boolPtr(true),   // 可订阅其他人
    }
    at.AddGrant(grant).SetIdentity(userID).SetName(nickname)
    return at.ToJWT()
}
```

### 7.3 客户端：语音连接流程

1. 用户进入房间 → 调用 `GET /rooms/:id` 获取房间信息
2. 请求 `POST /rooms/:id/livekit-token` 获取 LiveKit JWT
3. 使用 LiveKit Flutter SDK 连接：`LiveKitClient.connect(url, token)`
4. 默认只启用音频轨道，视频轨道默认不订阅
5. UI 层监听 `room.participants` 状态，实时显示在线成员和麦克风状态

```dart
// Flutter 客户端核心代码（伪代码）
final room = Room();
await room.connect(livekitUrl, livekitToken,
  roomOptions: RoomOptions(
    defaultAudioPublishOptions: AudioPublishOptions(
      name: 'microphone',
      dtx: true,  // 静音时降低带宽
    ),
  ),
);

// 开关麦
await room.localParticipant.setMicrophoneEnabled(!isMuted);
```

---

## 8. 语音连接地址管理

### 8.1 LiveKit URL 智能推导

客户端连接 LiveKit 语音房间时需获取正确的服务端地址（ws://IP:7880）。服务端采用两级推导策略确保公网和内网均能正确连接：

**级别 1：配置优先**
- 超管在 `deploy/config.yaml` 中手动填写 `livekit.public_url`（如 `ws://39.107.246.201:7880`）
- GetDetail 接口直接返回配置值，不再向外网查询（适合网络受限的云服务器）

**级别 2：自动推导**
- 若配置为空或为 localhost，GetDetail 从 HTTP 请求头 `X-Forwarded-Host` 提取客户端访问的 Host
- 剥离端口部分（如 `39.107.246.201:8080` → `39.107.246.201`）
- 拼接 LiveKit 标准端口 7880（`ws://39.107.246.201:7880`）

```go
// 服务端 room.go GetDetail 实现
var liveKitUrl string
publicURL := h.cfg.LiveKit.PublicURL
if publicURL != "" && !strings.Contains(publicURL, "localhost") && !strings.Contains(publicURL, "127.0.0.1") {
    liveKitUrl = publicURL  // 使用配置值
} else {
    host := c.GetHeader("X-Forwarded-Host")
    if host == "" {
        host = c.Request.Host  // 自动推导
    }
    hostOnly, _, _ := net.SplitHostPort(host)  // 剥离端口
    liveKitUrl = fmt.Sprintf("ws://%s:7880", hostOnly)  // 拼接 7880
}
```

此策略避免了向外网查询公网 IP（出站受限时会超时），同时通过自动推导满足多数部署场景需求。

---

## 9. 直播推流实现（LiveKit Ingress）

### 9.1 架构说明

原方案使用 SRS 接收 RTMP 推流，再通过 HTTP-FLV 下发给客户端，涉及两个独立媒体容器，客户端需要引入传统视频播放器（media_kit / flutter_vlc_player）。

**新方案使用 LiveKit Ingress**：OBS 将 RTMP 流推送给 Ingress 容器，Ingress 将其实时转码为 WebRTC Track 并注入对应的 LiveKit Room。客户端已经通过 LiveKit SDK 连接到该 Room，OBS 推流的画面作为一个普通 Participant Track 呈现，订阅方式与订阅其他人的语音/视频完全一致。

| 对比项 | SRS 方案（旧） | LiveKit Ingress 方案（新） |
|--------|--------------|--------------------------|
| 推流延迟 | 1-3 秒（HTTP-FLV） | < 200ms（WebRTC） |
| 客户端播放器 | media_kit / flutter_vlc_player | LiveKit SDK（已有） |
| 服务端容器数 | livekit + srs（2个大型容器） | livekit + livekit-ingress（1重1轻） |
| 多路流渲染逻辑 | 独立实现 | 与语音/视频共用同一套 Track 订阅逻辑 |
| 鉴权方式 | HTTP Callback（自维护） | LiveKit Ingress API（SDK 管理） |

### 9.2 推流创建流程（服务端）

房主在房间设置页点击"创建推流入口"时，服务端调用 LiveKit Ingress API 创建一个 RTMP Ingress 对象，并将返回的推流地址和 Stream Key 存入数据库后下发给客户端展示。

```
房主点击"创建推流入口"
        ↓
主服务调用 LiveKit Ingress API:
  livekit.CreateIngress(IngressInput_RTMP_INPUT, {
    name:     "OBS主推流",
    roomName: room.livekit_room_name,
    participantIdentity: "ingress_rm_a3f9b2_1",
  })
        ↓
LiveKit 返回:
  { ingressId, streamKey, url: "rtmp://server:1935/x/live" }
        ↓
主服务将 ingress_id / stream_key / rtmp_url 存入 room_ingresses 表
        ↓
返回给客户端：OBS 填写的推流服务器地址 + Stream Key
```

```go
// 服务端创建 Ingress（Go SDK 伪代码）
func CreateRoomIngress(roomName, label string) (*livekit.IngressInfo, error) {
    ingressClient := lksdk.NewIngressClient(livekitHost, apiKey, apiSecret)
    info, err := ingressClient.CreateIngress(ctx, &livekit.CreateIngressRequest{
        InputType:           livekit.IngressInput_RTMP_INPUT,
        Name:                label,
        RoomName:            roomName,
        ParticipantIdentity: "ingress_" + uuid.New().String(),
        ParticipantName:     label,
    })
    return info, err
}
```

### 9.3 OBS 推流配置（用户侧）

房主在客户端"房间设置 → 推流管理"页面创建推流入口后，将以下信息复制到 OBS：

```
推流服务器（Server）：rtmp://your-server-ip:1935/x/live
推流密钥（Stream Key）：rm_a3f9b2_sk_xxxxx   ← 由 LiveKit Ingress 生成，每个入口唯一
```

### 9.4 客户端直播流渲染

Ingress 推流进入 LiveKit Room 后，在 Room 内表现为一个 `RemoteParticipant`（身份标识为 `ingress_xxx`）。客户端通过 LiveKit SDK 监听新 Participant 加入事件，自动在侧边栏显示该推流条目。**无需额外播放器，直接使用已有的 LiveKit VideoTrack 渲染逻辑。**

```dart
// 监听新 Participant（含 Ingress 推流）加入
room.addListener(() {
  for (final participant in room.remoteParticipants.values) {
    if (participant.identity.startsWith('ingress_')) {
      // 这是一路 OBS 推流，加入侧边栏列表
      _addStreamToSidebar(participant);
    }
  }
});

// 用户点击后按需订阅视频轨道（与语音按需订阅逻辑完全一致）
Future<void> subscribeToStream(RemoteParticipant participant) async {
  for (final pub in participant.videoTrackPublications.values) {
    await pub.subscribe();  // 同一套 API，无需引入新依赖
  }
}
```

- **延迟**：WebRTC 端到端延迟 < 200ms，远优于 HTTP-FLV 的 1-3 秒
- **多路流**：多个 Ingress Participant 同时存在，侧边栏列表展示，点击切换主视窗，取消前一个的视频轨道订阅
- **屏幕共享**：同样通过 LiveKit SDK 发布 ScreenShare Track，客户端完全复用同一套渲染逻辑

### 9.5 视频流分辨率控制策略

不同来源的视频流具有不同的分辨率控制能力，需分别处理：

#### 屏幕共享轨道（Simulcast，完整支持）

屏幕共享由客户端通过 LiveKit SDK 发布，可开启 **Simulcast 联播**——SDK 在发布时自动编码出 Low（~320p）和 High（原画）两层质量的流，订阅端按需选择。

```dart
// 使用底层 API 发布屏幕共享并开启 Simulcast
// 注意：不使用高层 setScreenShareEnabled()，以便精确控制 Simulcast 参数
final screenTrack = await LocalVideoTrack.createScreenShareTrack(
  const ScreenShareCaptureOptions(
    params: VideoParametersPresets.screenShareH1080FPS15,
  ),
);
await room.localParticipant.publishVideoTrack(
  screenTrack,
  publishOptions: const VideoPublishOptions(
    simulcast: true,            // 发布 Low + High 两层
    videoSimulcastLayers: [
      VideoParametersPresets.h180_169,   // Low：侧边栏缩略图（~180p）
      VideoParametersPresets.h1080_169,  // High：主视窗全屏（1080p）
    ],
  ),
);
```

```dart
// 订阅端：根据显示状态动态切换画质层
class StreamViewController {
  // 侧边栏小窗 → 订阅 Low 层，节省带宽和解码资源
  Future<void> pinToSidebar(RemoteVideoTrackPublication pub) async {
    await pub.setVideoQuality(VideoQuality.LOW);
  }

  // 用户点击放大到主视窗 → 切换 High 层
  Future<void> expandToMain(RemoteVideoTrackPublication pub) async {
    await pub.setVideoQuality(VideoQuality.HIGH);
  }
}
```

#### OBS Ingress 推流（延迟订阅，折中方案）

LiveKit Ingress 接收到 OBS 的单路 RTMP 流后，注入 Room 内为**单层质量 Track**，无法生成 Simulcast 多层，因此无法做分辨率动态切换。采用以下折中策略，效果同样对用户友好：

| 状态 | 处理方式 |
|------|---------|
| 侧边栏（未选中） | **不订阅视频轨道**，侧边栏仅显示静态封面图（Ingress Participant 的元数据缩略图）和推流者昵称 |
| 用户点击进入主视窗 | 此时才调用 `pub.subscribe()` 订阅视频轨道，开始渲染完整画面 |
| 切换到其他流 / 关闭 | 调用 `pub.unsubscribe()` 立即取消订阅，释放解码资源 |

```dart
// OBS Ingress 推流的订阅管理
class IngressStreamController {
  RemoteVideoTrackPublication? _activePublication;

  // 用户点击侧边栏条目，切换到该 Ingress 推流
  Future<void> selectIngressStream(RemoteParticipant participant) async {
    // 1. 取消上一个流的订阅
    if (_activePublication != null) {
      await _activePublication!.unsubscribe();
      _activePublication = null;
    }

    // 2. 订阅新流（点击时才开始拉取视频数据）
    final pub = participant.videoTrackPublications.values.firstOrNull;
    if (pub != null) {
      await pub.subscribe();
      _activePublication = pub;
    }
  }

  // 用户关闭主视窗 / 切换到其他内容
  Future<void> closeStream() async {
    await _activePublication?.unsubscribe();
    _activePublication = null;
  }
}
```

> **小结**：屏幕共享实现真正的 Simulcast 分层渲染，OBS 推流通过延迟订阅达到类似的带宽节省效果。两种路径在 UI 层表现一致——侧边栏轻量，主视窗全质量——用户感知无差异。

---

---

## 8. 成员在线状态和说话状态检测

### 8.1 客户端实时状态流

客户端通过两个 Riverpod StreamProvider 维护实时的成员状态：

**speakingUsersProvider**：基于 LiveKit SDK 的 ActiveSpeakers 事件检测正在说话的用户
```dart
final speakingUsersProvider = StreamProvider<Set<int>>((ref) {
  final lk = ref.watch(livekitServiceProvider);
  return lk.speakingUsersStream;  // ActiveSpeakersChangedEvent → user ID set
});
```

**onlineUsersProvider**：基于 WebSocket member_join/member_leave 事件 + 定期 REST API 刷新（10s）维护在线用户 ID 集合
```dart
final onlineUsersProvider = StreamProvider<Set<int>>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  final ws = ref.watch(wsServiceProvider);
  final roomRepo = ref.watch(roomRepositoryProvider);
  
  // 初始化：REST API /rooms/:roomId/online-users
  // 监听：room.member_join / room.member_leave WS 事件
  // 定期刷新：every 10s as fallback
});
```

### 8.2 服务端在线用户端点

新增 `GET /api/v1/rooms/:roomId/online-users` 端点，返回当前房间在线用户 ID 列表（基于 WebSocket Hub 内存状态）：

```go
func (h *RoomHandler) OnlineUsers(c *gin.Context) {
    roomID := parseUint(c.Param("roomId"))
    userID := c.GetUint64("userID")
    
    // 权限检查
    if !h.roomRepo.IsMember(roomID, userID) {
        return  // 403
    }
    
    // 从 Hub 获取在线用户
    onlineUserIDs := h.hub.GetOnlineUsersInRoom(roomID)
    c.JSON(200, gin.H{
        "online_user_ids": onlineUserIDs,
    })
}
```

### 8.3 UI 表现

右侧面板成员列表根据状态排序和展示：

```
【在线成员列表】 (3/5)  ← 在线人数 / 总人数
├─ Alice      🔴🟢  ← 绿点说话中（呼吸灯动画），圆圈标记在线
├─ Bob        🟢      ← 绿点静止（在线但未说话）
├─ Charlie    ⚪     ← 灰点离线
└─ David      ⚪
```

- 在线成员排在前面（通过 member_join / member_leave 更新排序）
- 离线成员降低透明度（`opacity: 0.45`）
- 说话中的成员头像周围有绿色发光边框（Simulcast 呼吸灯动画）
- 房主 (role=owner) 在同组内优先排列

---

# 第七章 VLAN 虚拟局域网实现

## 9. VLAN 技术方案

### 9.1 方案说明

VLAN 功能基于 WireGuard VPN 协议实现，完全内嵌于客户端安装包中，用户无需安装任何额外软件。服务端运行一个 WireGuard 实例作为 Hub，客户端通过 Platform Channel 调用内嵌的 `wireguard-go` 库建立隧道。

### 9.2 组件说明

| 组件 | 运行位置 | 作用 |
|------|---------|------|
| WireGuard 服务端 | Docker 容器（服务器） | 作为 VPN Hub，维护所有 Peer 的路由，虚拟IP段由 config.yaml 中 `wireguard.subnet` 配置（默认 10.0.8.0/24，可改为 172.29.0.0/24 等避免冲突） |
| WireGuard 协调服务 | Golang 主服务内 | 管理 Peer 注册、IP 分配、密钥下发，与 WG 实例通过 wgctrl 通信 |
| wireguard-go（客户端） | Flutter 客户端（内嵌） | 纯 Go 实现的 WireGuard 用户态实现，通过 Platform Channel 调用 |
| wintun.dll（Windows） | 客户端安装包内置 | Windows 虚拟网卡驱动，安装包阶段静默安装 |

### 9.3 VLAN 建立流程

1. 用户在房间内点击"开启联机组网"开关
2. 客户端在本地生成 WireGuard 密钥对（公钥/私钥）
3. 客户端调用 `POST /rooms/:id/vlan/join`，上传公钥
4. 服务端协调服务：分配虚拟 IP、将新 Peer 注册到服务端 WireGuard 实例、返回配置
5. 服务端通过 WebSocket 广播 `vlan.peer_update` 事件，通知房间内其他成员新 Peer 加入
6. 客户端通过 Platform Channel 启动 wireguard-go，应用配置建立隧道
7. 隧道建立完成，房间内用户可通过各自分配的虚拟 IP 地址互相访问，游戏局域网功能生效（默认网段 10.0.8.x，可在 config.yaml 中修改）

### 9.4 Flutter Platform Channel 实现

```dart
// Dart 层调用
class WireGuardService {
  static const _channel = MethodChannel('nexusroom/wireguard');

  // 启动 WireGuard 隧道
  static Future<void> startTunnel(WgConfig config) async {
    await _channel.invokeMethod('startTunnel', config.toMap());
  }

  // 停止隧道
  static Future<void> stopTunnel() async {
    await _channel.invokeMethod('stopTunnel');
  }

  // 生成密钥对（由 native 层生成，更安全）
  static Future<KeyPair> generateKeyPair() async {
    final result = await _channel.invokeMethod('generateKeyPair');
    return KeyPair.fromMap(result);
  }
}
```

### 9.5 IP 分配规则

- **服务端 VPN Hub**：子网网关地址，默认 `10.0.8.1`（与 `wireguard.subnet` 联动）
- **客户端分配范围**：子网内 `.2 ~ .254`，最多 253 个同房间 VLAN 成员
- **每个房间**使用独立的 WireGuard 网络命名空间（或通过 AllowedIPs 隔离）
- **IP 分配策略**：按注册顺序递增分配，用户离开后 IP 释放回池，10 分钟后可被复用

### 9.6 网段冲突风险与配置

> **⚠️ 重要**：若服务端默认使用的 `10.0.8.0/24` 网段与用户物理局域网网段重叠（如家用路由器也在 `10.0.x.x` 段），WireGuard 会将原本应走物理网卡的流量全部劫持到虚拟网卡，导致用户网络中断、VLAN 功能失效。

**判断方法**：用户在本机执行 `ipconfig`（Windows）或 `ip route`（macOS/Linux），查看是否存在 `10.0.8.x` 段的路由条目。

**解决方式**：超管在服务端 `config.yaml` 中修改 `wireguard.subnet` 和 `wireguard.gateway_ip` 为不冲突的私有网段：

```yaml
# 常用备选网段（选择一个与用户物理网络不冲突的）
wireguard:
  subnet: "172.29.0.0/24"    # 推荐备选
  gateway_ip: "172.29.0.1"

# 其他可选：
#   subnet: "192.168.200.0/24"  gateway_ip: "192.168.200.1"
#   subnet: "10.88.0.0/24"      gateway_ip: "10.88.0.1"
```

**修改后的影响**：
- 修改需重启服务端（`docker compose restart server`）
- 所有当前活跃的 VLAN 连接会断开，成员需重新点击"开启联机组网"执行 join
- Web 管理后台在保存此配置时应弹出确认警告：**"修改子网段将断开所有当前 VLAN 连接，确认继续？"**

> **注意**：Windows 下 wintun 驱动加载需要管理员权限，建议在安装包（NSIS/Inno Setup）的安装阶段以管理员权限静默安装驱动，运行时不再需要提权。

---

# 第八章 客户端架构详解

## 10. 客户端核心设计

### 10.1 首次启动流程

1. 检查本地 SQLite 是否存在 `server_url` 配置
2. 不存在 → 显示"服务器配置"页面，用户填入 `http(s)://ip:port`
3. 客户端发送 `GET /ping` 验证连通性，成功则保存 `server_url`
4. 跳转到登录/注册页面
5. 登录成功后保存 JWT token，进入主界面

> `server_url` 保存在本地 SQLite 的 `settings` 表中。客户端设置页面提供"更改服务器"入口，更换后清除本地缓存并重新登录。

**本地数据库存储路径**（使用 Drift + path_provider）：
- **Windows**：`%USERPROFILE%\Documents\nexusroom.sqlite`
- **macOS**：`~/Documents/nexusroom.sqlite`
- **清除数据**：删除该文件或执行 `flutter clean`

### 10.2 WebSocket 连接管理与房间状态同步

客户端维护一个全局单例 `WebSocketService`，连接断开时自动进行指数退避重连（1s → 2s → 4s → 8s → 最大 30s）。

**关键机制：重连后自动重新加入房间**

为解决 WebSocket 重连后服务端创建新 `Client` 实例（`rooms` map 为空）导致的"用户在房间内但无法发送/接收消息"问题，实现三层防御机制：

1. **`_joinedRooms` 追踪**：客户端维护一个 `Set<int>` 记录所有已调用 `joinRoom()` 的房间 ID
2. **`connected` 事件自动重新加入**：收到服务端的 `connected` 确认事件后，自动对 `_joinedRooms` 中的所有房间重新发送 `room.join` 消息
3. **`chat.error(not_in_room)` 兜底**：若上述重连逻辑遗漏，服务端返回 `chat.error` 时客户端立即重新加入该房间并重试发送

```dart
class WebSocketService extends StateNotifier<WsState> {
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final Set<int> _joinedRooms = {};  // 追踪已加入的房间

  // 加入房间时记录
  void joinRoom(int roomId) {
    _joinedRooms.add(roomId);
    sendEvent('room.join', {'room_id': roomId});
  }

  // 离开房间时移除
  void leaveRoom(int roomId) {
    _joinedRooms.remove(roomId);
    sendEvent('room.leave', {'room_id': roomId});
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    final delay = min(30, pow(2, _reconnectAttempts)).toInt();
    _reconnectTimer = Timer(Duration(seconds: delay), _connect);
    _reconnectAttempts++;
  }

  void _onConnected() {
    _reconnectAttempts = 0;
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sendEvent('heartbeat', {}),
    );
    
    // ⚠️ 关键：重新加入所有已加入的房间
    for (final roomId in _joinedRooms) {
      debugPrint('[WsService] Re-joining room $roomId after reconnect');
      sendEvent('room.join', {'room_id': roomId});
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final event = data['event'];
    final payload = data['payload'];

    // 兜底：收到 chat.error(not_in_room) 时自动重新加入
    if (event == 'chat.error' && payload != null) {
      final roomId = payload['room_id'];
      final reason = payload['reason'];
      if (reason == 'not_in_room' && roomId != null) {
        debugPrint('[WsService] chat.error: not in room $roomId, rejoining...');
        joinRoom(roomId);  // 立即重新加入
      }
    }

    // 其他事件处理...
  }
}
```

### 10.3 AppShell 集中式房间 Join/Leave 管理

**背景问题**：在 GoRouter 的 ShellRoute 架构下，房间页面（`RoomDetailPage`）在 `initState` 中调用 `joinRoom()` 存在上下文丢失问题——页面销毁后无法调用 `dispose()` 中的 `leaveRoom()`，且重复进入同一房间 ID 时 `initState` 不会触发。

**解决方案**：将房间 join/leave 逻辑提升到 `AppShell`（ShellRoute 的外层容器），通过监听路由变化统一管理：

```dart
// app/shell/app_shell.dart（ConsumerStatefulWidget）
class _AppShellState extends ConsumerState<AppShell> {
  String? _currentRoomId;

  @override
  void initState() {
    super.initState();
    _syncRoom(widget.location);  // 初始化时同步房间状态
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⚠️ 监听 location 属性变化（从 ShellRoute builder 传入）
    if (oldWidget.location != widget.location) {
      _syncRoom(widget.location);
    }
  }

  void _syncRoom(String location) {
    final roomId = _extractRoomId(location);  // 从 URL 提取 roomId
    if (roomId != _currentRoomId) {
      final oldRoomId = _currentRoomId;
      _currentRoomId = roomId;
      
      // 使用 post-frame callback 确保 Provider 已初始化
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ws = ref.read(wsServiceProvider);
        
        // 离开旧房间
        if (oldRoomId != null) {
          ws.leaveRoom(int.parse(oldRoomId));
        }
        // 加入新房间
        if (roomId != null) {
          ws.joinRoom(int.parse(roomId));
        }
      });
    }
  }

  String? _extractRoomId(String location) {
    // 解析 /rooms/123 或 /rooms/123/settings
    final match = RegExp(r'/rooms/(\d+)').firstMatch(location);
    return match?.group(1);
  }
}
```

**关键点**：
- `location` 属性由 `ShellRoute` builder 显式传入（`state.uri.toString()`），避免在 `AppShell` 内部调用 `GoRouterState.of(context)` 导致的上下文错误
- `didUpdateWidget` 确保路由切换时可靠触发（比 `GoRouter` 的 listener 更稳定）
- `addPostFrameCallback` 避免在 build 阶段读取 Provider
- **双保险设计**：`RoomDetailPage` 的 `initState`/`dispose` 仍保留 join/leave 调用作为冗余安全网（服务端 join/leave 操作是幂等的）

### 10.4 路由配置（GoRouter）

| 路由路径 | 页面 | 守卫 |
|---------|------|------|
| /setup | 服务器配置页 | 未配置 server_url 时强制跳转 |
| /login | 登录/注册页 | 未登录时跳转 |
| /home | 首页（房间列表） | 已登录 |
| /rooms/:id | 房间主界面 | 已登录 + 已是成员 |
| /rooms/:id/settings | 房间设置（房主） | 已登录 + 房主 |
| /settings | 客户端设置 | 已登录 |
| /admin | 超管面板（跳转Web后台） | 已登录 + 超管角色 |

**GoRouter ShellRoute 配置要点**：

```dart
// app/router/app_router.dart
ShellRoute(
  builder: (context, state, child) {
    // ⚠️ 必须显式传递 location，不要在 AppShell 内部调用 GoRouterState.of(context)
    return AppShell(
      location: state.uri.toString(),  // 关键：显式传递当前路由
      child: child,
    );
  },
  routes: [
    GoRoute(path: '/rooms/:id', builder: ...),
    GoRoute(path: '/rooms/:id/settings', builder: ...),
    // ...
  ],
)
```

### 10.5 消息本地缓存与增量同步

增量同步使用自增主键 `id` 作为锚点，而非 `created_at` 时间戳。这样可以彻底规避三类问题：

- **时钟漂移**：服务器与客户端时间不完全一致时，时间戳比较会产生偏差
- **高并发同秒写入**：同一秒内多条消息写入数据库，顺序不确定，按时间戳过滤极易漏消息
- **时区问题**：客户端本地时区转换增加不必要的复杂度

**服务端 API 调整**：`GET /rooms/:roomId/messages` 使用 `after_id` 参数（而非 `after` 时间戳）：

```
GET /api/v1/rooms/5/messages?after_id=1234&limit=50
```

服务端 SQL：`WHERE id > $after_id ORDER BY id ASC LIMIT $limit`，简单高效，有索引保障。

```dart
// 增量同步逻辑（伪代码）
Future<void> syncMessages(int roomId) async {
  // 1. 查询本地最大消息 id（不再使用时间戳）
  final lastId = await db.getMaxMessageId(roomId) ?? 0;

  // 2. 向服务端请求 id > lastId 的消息
  final msgs = await api.getMessages(
    roomId: roomId,
    afterId: lastId,   // 改用 after_id
    limit: 100,
  );

  // 3. 批量写入本地数据库（UPSERT，防重复）
  await db.upsertMessages(msgs);

  // 4. 如果返回了 100 条（可能还有更多），继续拉取
  if (msgs.length == 100) {
    await syncMessages(roomId);  // 递归直到拉完
  }
}
```

> **注意**：客户端写入本地数据库时使用 UPSERT（`INSERT OR REPLACE`），防止 WebSocket 实时推送与增量同步之间产生重复消息。

### 10.6 房间主界面 UI 布局

```
┌──────────────────────────────────────────────────────────────┐
│  左侧边栏 (220px)  │          主内容区          │ 右侧栏(200px) │
│                    │                            │              │
│  [房间名称]        │  ┌──────────────────────┐  │  [在线成员]  │
│  ─────────────     │  │                      │  │  • Alice 🎤 │
│  📺 直播列表       │  │   主视窗              │  │  • Bob  🔇  │
│  > OBS主流 🔴      │  │  (点击直播流后显示)   │  │  • Carol🎤  │
│  > 屏幕共享        │  │                      │  │             │
│                    │  └──────────────────────┘  │  ─────────  │
│  ─────────────     │                            │  [VLAN]     │
│  ⚙️ 房间设置       │  ┌──────────────────────┐  │  已开启 ✅  │
│                    │  │    消息区域           │  │  10.0.8.5   │
│                    │  │    ...               │  │             │
│  ─────────────     │  │    消息输入框 [发送]  │  │             │
│  🎤 [静音]  [VLAN] │  └──────────────────────┘  │             │
└──────────────────────────────────────────────────────────────┘
```

### 10.7 后台挂起资源管理

当用户将 NexusRoom 最小化到系统托盘，或切换到全屏游戏被完全遮挡时，若客户端继续解码多路视频流会持续占用 GPU/CPU，直接影响游戏帧率。通过监听窗口状态变化，在后台时自动暂停所有视频解码，恢复前台时重新唤醒，对游戏玩家体验提升显著。

#### 依赖

```yaml
# pubspec.yaml
dependencies:
  window_manager: ^0.3.0    # Flutter Desktop 窗口状态监听
```

#### 实现

```dart
// lib/core/window/window_lifecycle_service.dart

class WindowLifecycleService with WindowListener {
  final LiveKitRoomService _roomService;
  bool _isBackground = false;

  WindowLifecycleService(this._roomService) {
    windowManager.addListener(this);
  }

  // ── 进入后台：窗口最小化 ──────────────────────────────────────
  @override
  void onWindowMinimize() => _enterBackground();

  // ── 进入后台：失去焦点（被全屏游戏遮挡）────────────────────────
  // 加 1 秒延迟，避免窗口切换过渡期误触发
  @override
  void onWindowBlur() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!await windowManager.isFocused()) _enterBackground();
    });
  }

  // ── 恢复前台 ────────────────────────────────────────────────
  @override
  void onWindowFocus() => _exitBackground();

  @override
  void onWindowRestore() => _exitBackground();

  // ── 核心逻辑 ────────────────────────────────────────────────
  void _enterBackground() {
    if (_isBackground) return;
    _isBackground = true;

    final room = _roomService.currentRoom;
    if (room == null) return;

    // 暂停所有远端视频轨道解码
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications.values) {
        pub.track?.disable();       // 停止解码，但保留订阅关系
      }
    }

    // 降低 Flutter UI 渲染帧率（后台无需 60fps 刷新）
    // 注意：音频轨道不受影响，语音通话正常进行
    debugPrint('[Window] 进入后台，已暂停所有视频解码');
  }

  void _exitBackground() {
    if (!_isBackground) return;
    _isBackground = false;

    final room = _roomService.currentRoom;
    if (room == null) return;

    // 仅恢复当前主视窗正在显示的视频轨道
    // 侧边栏的流仍保持暂停，避免不必要的解码开销
    final activeParticipant = _roomService.activeStreamParticipant;
    if (activeParticipant != null) {
      for (final pub in activeParticipant.videoTrackPublications.values) {
        if (pub.subscribed) pub.track?.enable();
      }
    }

    debugPrint('[Window] 恢复前台，已唤醒主视窗视频解码');
  }

  void dispose() {
    windowManager.removeListener(this);
  }
}
```

#### 行为总结

| 窗口状态 | 音频 | 主视窗视频 | 侧边栏视频 |
|---------|------|-----------|-----------|
| 前台（正常） | ✅ 正常 | ✅ 解码渲染 | ⏸ 暂停（按需订阅） |
| 最小化 / 后台 | ✅ 正常 | ⏸ 暂停解码 | ⏸ 暂停 |
| 恢复前台 | ✅ 正常 | ✅ 自动唤醒 | ⏸ 暂停（需点击才恢复） |

> **音频始终保持运行**：无论窗口处于何种状态，语音通话和消息 WebSocket 连接均不受影响。后台挂起只针对视频解码这一高资源消耗环节。

---

# 第九章 服务端配置与部署

## 11. 服务端配置文件

### 11.1 config.yaml 完整示例

```yaml
# NexusRoom Server Configuration
# 首次部署后修改此文件，重启服务生效

server:
  port: 8080                      # 主服务 HTTP 端口
  mode: release                   # debug / release
  domain: ""                      # 可选，配置域名后启用 HTTPS

database:
  host: postgres                  # Docker 服务名
  port: 5432
  name: nexusroom
  user: nexusroom
  password: "your-db-password"    # 请修改此密码

redis:
  host: redis
  port: 6379
  password: ""

auth:
  jwt_secret: "your-jwt-secret"   # 请修改，至少32位随机字符串
  jwt_expire_hours: 720           # Token 有效期（30天）
  admin_token: ""                 # 填写后，持有此 token 注册的用户获得超管权限
                                  # 首个超管注册后建议清空此字段

message:
  retention_days: 30              # 消息保留天数（0=永久）

livekit:
  url: ws://livekit:7880          # Docker 内网访问
  api_key: "your-livekit-key"
  api_secret: "your-livekit-secret"

livekit_ingress:
  rtmp_port: 1935                 # Ingress 容器对外暴露的 RTMP 接收端口
  # LiveKit Ingress 使用与 livekit 相同的 api_key / api_secret，无需单独配置

wireguard:
  server_ip: "your-server-public-ip"  # 服务器公网IP，客户端连接用
  listen_port: 51820
  server_private_key: ""          # 首次启动时自动生成并写入
  subnet: "10.0.8.0/24"          # ⚠️ 可配置！若与用户物理网段冲突（如家用路由器也用 10.0.8.x）
                                  # 请修改为不冲突的私有段，如 "172.29.0.0/24"
                                  # 修改后需重启服务端，所有 VLAN 成员重新执行 join 操作
  gateway_ip: "10.0.8.1"         # 与 subnet 第一个地址保持一致

storage:
  path: ./data/uploads            # 文件上传存储路径
  max_file_size_mb: 20
```

---

## 12. Docker Compose 部署

### 12.1 docker-compose.yml

```yaml
version: '3.9'
services:
  server:
    image: nexusroom-server:latest
    ports:
      - "8080:8080"
      - "51820:51820/udp"   # WireGuard
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./data:/app/data
    depends_on: [postgres, redis, livekit, livekit-ingress]
    cap_add: [NET_ADMIN]           # WireGuard 需要
    sysctls:
      - net.ipv4.ip_forward=1

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: nexusroom
      POSTGRES_USER: nexusroom
      POSTGRES_PASSWORD: ${DB_PASSWORD:-nexusroom_password}
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    volumes: [redisdata:/data]

  livekit:
    image: livekit/livekit-server:latest
    ports:
      - "7880:7880"
      - "7881:7881"
      - "50000-50050:50000-50050/udp"  # WebRTC UDP 端口范围（50 个端口≈25路并发流，小圈子足够）
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml
    command: --config /etc/livekit.yaml

  # ⚠️  端口说明：docker-compose 中暴露的 UDP 端口范围必须与
  #    livekit.yaml 中的 port_range_start / port_range_end 保持一致，
  #    否则 LiveKit 进程内分配的端口和容器暴露的端口对不上，WebRTC 连接会失败。
  #
  # livekit.yaml 中需同步配置：
  #   rtc:
  #     port_range_start: 50000
  #     port_range_end:   50050
  #     node_ip: YOUR_PUBLIC_IP  # ← 【重要】改为 true 会导致启动时向外网查询 IP，出站受限的服务器会超时崩溃
  #     use_external_ip: false
  #
  # 云服务器（阿里云/腾讯云）安全组需放行 50000-50050/UDP，
  # 大范围 UDP 端口段可能被云厂商误判为 UDP 泛洪，建议保持范围尽量小。

  livekit-ingress:
    image: livekit/ingress:latest
    ports:
      - "1935:1935"         # RTMP 推流接收端口（OBS 推流到此）
    environment:
      - INGRESS_CONFIG_BODY=|
          api_key: your-livekit-key
          api_secret: your-livekit-secret
          ws_url: ws://livekit:7880
          rtmp_port: 1935
          logging:
            level: info
    depends_on: [livekit]
    # Ingress 容器极轻量，内存占用远低于 SRS

  web-admin:
    image: nexusroom-web-admin:latest
    ports:
      - "3000:80"           # Web 管理后台

volumes:
  pgdata:
  redisdata:
```

**环境变量配置（.env 文件）：**

docker-compose.yml 中使用了环境变量（如 `${DB_PASSWORD:-nexusroom_password}`），需要在 `deploy/` 目录创建 `.env` 文件：

```bash
# deploy/.env
DB_PASSWORD=nexusroom_password
LIVEKIT_API_KEY=your-livekit-key
LIVEKIT_API_SECRET=your-livekit-secret
```

> 如果不创建 `.env` 文件，Docker Compose 会使用默认值（`:-` 后面的值）。但如果环境变量没有默认值且 `.env` 文件不存在，会导致 PostgreSQL 认证失败。建议始终显式创建 `.env` 文件。

### 12.2 服务端一键部署脚本

```bash
#!/bin/bash
# deploy.sh
set -e

echo '🚀 NexusRoom Server 部署脚本'

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo '错误: 请先安装 Docker'
    exit 1
fi

# 生成随机密码和密钥（如果 config.yaml 不存在）
if [ ! -f config.yaml ]; then
    cp config.yaml.template config.yaml
    sed -i "s/your-db-password/$(openssl rand -hex 16)/" config.yaml
    sed -i "s/your-jwt-secret/$(openssl rand -hex 32)/" config.yaml
    echo '✅ config.yaml 已生成，请编辑 wireguard.server_ip 为本机公网IP'
fi

docker compose pull
docker compose up -d
echo '✅ 部署完成！管理后台: http://localhost:3000'
```

---

# 第十章 开发路线图

## 13. 分阶段开发计划

### 第一阶段：基础设施 + IM

**后端任务**

- Docker Compose 配置编写，验证所有服务可启动
- Golang 项目初始化：Gin + GORM + 配置加载
- 数据库迁移：users / rooms / room_members / messages 表
- 认证模块：注册（含 admin_token 逻辑）、登录、JWT 生成与验证
- 房间模块：创建、加入（邀请码）、获取详情、踢出成员
- 消息模块：HTTP 接口存储和分页查询消息，WebSocket Hub 实现消息广播
- WebSocket：连接管理、心跳、`chat.message` 事件广播
- 消息清理 cron job：按 `retention_days` 定期清理

**客户端任务**

- Flutter 项目初始化：依赖配置、GoRouter、Riverpod
- 本地 SQLite（drift）初始化：settings 表、messages 表
- 服务器配置页：填写 IP、/ping 连通性验证、保存
- 登录/注册页面
- 房间列表页、创建/加入房间流程
- 房间主界面：消息列表、消息输入（文字+图片）、成员侧边栏
- WebSocket 连接管理、消息接收与本地存储、断线重连
- 增量消息同步

**阶段验收标准**
> ✅ 两台电脑可以通过局域网 IP 配置客户端连接同一服务端，注册账户，创建/加入房间，互发消息。

---

### 第二阶段：音视频集成

**后端任务**

- 集成 `livekit-server-sdk-go`，实现 token 生成接口
- LiveKit Ingress 容器部署配置
- 推流入口管理 API：`POST/GET/DELETE /rooms/:id/ingresses`，内部调用 LiveKit Ingress SDK
- WebSocket 新增 `voice.state_update` 事件处理
- 注：stream.new / stream.ended 事件已废弃，Ingress 推流状态由客户端通过 LiveKit SDK 直接感知

**客户端任务**

- 集成 `livekit_client` Flutter SDK
- 语音频道：进入房间自动连接 LiveKit，默认只订阅音频轨道
- 静音/开麦 UI 控件，广播语音状态变更
- 成员列表显示说话/静音状态（音量指示动效）
- 直播侧边栏：监听 LiveKit Room 中 identity 以 `ingress_` 开头的 Participant，列表展示推流条目
- 主视窗复用 LiveKit VideoTrack 渲染（无需引入额外播放器）
- 房间设置页：推流入口管理（创建/删除 Ingress，展示 OBS 填写的地址和 Stream Key）
- OBS Ingress 推流的延迟订阅策略（侧边栏不订阅视频，点击主视窗时才 subscribe）
- `WindowLifecycleService` 实现（集成 window_manager，最小化/失焦时 disable 所有视频轨道）

**阶段验收标准**
> ✅ 多人可在房间内语音通话；OBS 可通过 RTMP 向房间推流，客户端可点击观看直播；最小化后游戏帧率不受客户端影响。

---

### 第三阶段：管理功能与扩展接口

**后端任务**

- 超管 API 全部实现（用户管理、房间管理、配置修改）
- 好友系统：申请、接受/拒绝、好友列表、邀请进房间
- 用户头像上传接口
- QQ 机器人 Webhook 接口（兼容 OneBot 格式）
- Webhook secret 配置和验证

**Web 管理后台任务**

- Vue 3 项目初始化，配置 Axios 请求超管 API
- 仪表盘、用户管理、房间管理、配置中心页面全部实现
- 构建为静态文件，集成到 Docker Compose

**客户端任务**

- 好友系统 UI：通过 display_id 搜索用户、添加好友、邀请进房间
- 头像上传、昵称修改
- 客户端设置页：更换服务器、退出登录

**阶段验收标准**
> ✅ Web 管理后台可访问并管理所有房间和用户；QQ 机器人可向指定房间发送消息。

---

### 第四阶段：VLAN 与屏幕共享

**VLAN 后端任务**

- 服务端 WireGuard 实例初始化（首次启动自动生成密钥对并写入 config.yaml）
- WireGuard 协调服务：wgctrl 集成、IP 分配池、Peer 注册/注销
- VLAN API 实现（join / leave / peers）
- WebSocket `vlan.peer_update` 事件广播

**VLAN 客户端任务**

- Windows Platform Channel 实现：wireguard-go 集成、wintun 驱动静默安装（安装包级别）
- macOS Platform Channel 实现：wireguard-go 用户态实现
- WireGuard 配置文件生成与应用
- VLAN UI：开关控件、当前虚拟 IP 显示、成员虚拟 IP 列表

**屏幕共享任务（视 LiveKit Flutter SDK 桌面端支持情况）**

- 评估 `livekit_client` 在 Windows/macOS 的屏幕采集支持
- 如支持：发布屏幕共享轨道时开启 Simulcast（Low 层 180p 用于侧边栏，High 层 1080p 用于主视窗）
- 实现 `StreamViewController.pinToSidebar()` / `expandToMain()` 分辨率切换逻辑（调用 `setVideoQuality`）
- 如不支持：作为后续版本，本阶段跳过，不影响其他功能

**阶段验收标准**
> ✅ 房间内用户点击"开启组网"后，可通过各自分配的虚拟 IP 地址互 ping（默认段 10.0.8.x，可配置），游戏内局域网联机功能正常。

---

# 第十一章 开发规范

## 16. 编码规范

### 16.1 Golang 后端规范

- 遵循标准 Go 项目布局（cmd/internal/pkg）
- 使用 `golangci-lint` 进行代码检查，配置文件提交到仓库
- 错误处理：错误必须被处理或向上传递，禁止忽略 error 返回值
- 数据库操作统一通过 Repository 层，禁止在 Handler 层直接操作数据库
- 所有对外接口必须有参数校验（使用 `validator` 库）
- HTTP Handler 只负责请求解析和响应序列化，业务逻辑放在 Service 层
- 配置通过结构体注入，禁止在业务代码中直接读取环境变量或配置文件

### 16.2 Flutter 客户端规范

- 严格遵循 Feature-First 目录结构，每个功能独立封装
- 状态管理统一使用 Riverpod 2.x，禁止使用 `setState` 处理跨组件状态
- 网络请求统一通过 Repository 层封装，Provider 层不直接调用 HTTP
- 本地存储统一通过 drift 数据库，`shared_preferences` 仅存设置项
- 所有异步操作必须处理错误状态，UI 层显示对应的错误提示
- Widget 拆分原则：单个 Widget 文件不超过 200 行
- 命名规范：文件名用下划线（snake_case），类名用大驼峰（PascalCase）

### 16.3 API 版本管理

- 所有接口以 `/api/v1` 为前缀，后续版本迭代使用 `/api/v2`
- 字段废弃时先标记 deprecated，保留至少一个版本周期后再删除
- WebSocket 消息的 event 字段名变更需要向后兼容

### 16.4 安全规范

- **密码存储**：使用 bcrypt，cost 值不低于 12
- **JWT Secret**：生产环境必须使用随机生成的 32 字节以上字符串
- **文件上传**：校验文件类型（通过 MIME type，非扩展名），限制文件大小，文件名随机化存储
- **SQL 注入**：统一使用 GORM 的参数化查询，禁止字符串拼接 SQL
- **推流密钥**：由 LiveKit Ingress API 统一生成，服务端仅存储并转发，不自行生成。若有其他需要本地生成随机 token 的场景（如 Webhook secret），使用 `crypto/rand`，不使用 `math/rand`
- **内网接口**：`/internal/*` 仅允许内网容器访问（原 SRS HTTP Callback 已移除，此路由可保留供未来内部组件使用），通过 IP 白名单中间件限制

### 16.5 Git 提交规范（Conventional Commits）

| 类型 | 说明 | 示例 |
|------|------|------|
| feat | 新功能 | feat(room): add invite code generation |
| fix | Bug 修复 | fix(auth): token expiry not checked correctly |
| refactor | 重构（无功能变更） | refactor(ws): extract hub into separate package |
| docs | 文档更新 | docs: update API spec for room endpoints |
| chore | 构建/依赖/配置 | chore: update docker compose to v3.9 |
| test | 测试相关 | test(service): add unit tests for message service |

---

# 附录

## 附录A：QQ 机器人 Webhook 接口

### 接口定义

```
POST /webhook/qq
Header: Authorization: Bearer {webhook_secret}
```

```json
// Request Body（OneBot-compatible 格式）
{
  "room_id": 5,
  "sender": {
    "user_id": "12345678",
    "nickname": "张三"
  },
  "message_type": "text",
  "content": "这是来自QQ的消息"
}

// Response
{ "code": 200, "message": "ok" }
```

> 来自 QQ 机器人的消息在客户端 UI 中以特殊样式展示（显示 [QQ] 标签和 QQ 昵称），与普通用户消息区分。

---

## 附录B：依赖包清单

### Golang 后端主要依赖

| 包名 | 用途 |
|------|------|
| github.com/gin-gonic/gin | HTTP 框架 |
| github.com/gorilla/websocket | WebSocket 处理 |
| gorm.io/gorm + gorm.io/driver/postgres | ORM + PostgreSQL 驱动 |
| github.com/redis/go-redis/v9 | Redis 客户端 |
| github.com/golang-jwt/jwt/v5 | JWT 生成与验证 |
| golang.org/x/crypto/bcrypt | 密码哈希 |
| github.com/livekit/server-sdk-go | LiveKit 管理 SDK |
| golang.zx2c4.com/wireguard | WireGuard Go 实现 |
| golang.zx2c4.com/wireguard/wgctrl | WireGuard 控制接口 |
| github.com/go-playground/validator/v10 | 参数校验 |
| github.com/robfig/cron/v3 | 定时任务（消息清理） |
| github.com/spf13/viper | 配置文件加载 |

### Flutter 客户端主要依赖

| 包名 | 用途 |
|------|------|
| flutter_riverpod / riverpod_annotation | 状态管理 |
| go_router | 路由管理 |
| drift + drift_flutter | 本地 SQLite ORM |
| dio | HTTP 客户端 |
| web_socket_channel | WebSocket 客户端 |
| livekit_client | LiveKit WebRTC SDK（语音、OBS推流、屏幕共享统一渲染，无需独立播放器） |
| image_picker | 图片选择 |
| cached_network_image | 网络图片缓存 |
| window_manager | Flutter Desktop 窗口状态监听（最小化/失焦检测，后台挂起视频解码） |
| screen_capturer（可选） | 屏幕采集（屏幕共享阶段） |

---

## 附录C：端口说明

| 端口 | 协议 | 服务 | 说明 |
|------|------|------|------|
| 8080 | TCP | Golang 主服务 | REST API + WebSocket，客户端连接此端口 |
| 1935 | TCP | LiveKit Ingress | RTMP 推流接收，OBS 向此端口推流，Ingress 转码为 WebRTC Track |
| 7880 | TCP | LiveKit | WebRTC 信令，客户端语音/视频连接 |
| 50000-50050 | UDP | LiveKit | WebRTC 媒体流 UDP 端口范围（约 25 路并发流，与 livekit.yaml port_range 必须保持一致） |
| 51820 | UDP | WireGuard | VLAN 虚拟局域网 VPN 端口 |
| 3000 | TCP | Web 管理后台 | Nginx 托管的 Vue 静态文件 |
| 5432 | TCP | PostgreSQL | 仅容器内网访问，不对外暴露 |
| 6379 | TCP | Redis | 仅容器内网访问，不对外暴露 |

## 附录D：防火墙配置参考

```bash
# 开放必要端口（以 UFW 为例）
ufw allow 8080/tcp         # 主服务
ufw allow 1935/tcp         # RTMP 推流（LiveKit Ingress 接收）
ufw allow 7880/tcp         # LiveKit 信令
ufw allow 50000:50050/udp  # LiveKit 媒体（与 docker-compose 和 livekit.yaml 保持一致）
ufw allow 51820/udp        # WireGuard VLAN
ufw allow 3000/tcp         # Web 管理后台（可选，仅管理员访问）

# PostgreSQL 和 Redis 不对外暴露（仅容器内网）
```

---

*NexusRoom Technical Documentation v1.3.4*
