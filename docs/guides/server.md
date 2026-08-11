# 服务端开发指南

本文档说明 NexusRoom `3.0.0` 单体服务端。完整系统设计见 [NexusRoom 技术规范](../NexusRoom.md)，构建发布见 [服务端编译与打包](../build/server-build.md)。桌面客户端为 Electron + React + TypeScript，开发和打包命令见 [客户端开发指南](client.md)。

## 运行边界

服务端是单一 NexusRoom 服务，同时提供 REST API、WebSocket、SQLite、Opus 语音 SFU、RTMP 接入、HTTP-FLV、浏览器 WebRTC 播放、STUN/TURN、WireGuard 协调和内嵌网页。主进程按活动 AAC 源流管理 FFmpeg 音频工作进程，仍由同一个容器或 systemd 服务统一配置和管理。运行时不依赖 PostgreSQL、Redis、LiveKit Server、SRS 或 nginx。

## 源码目录

```text
server/
├── cmd/server/                    进程装配、启动和优雅关闭
├── internal/api/                  REST、WebSocket 和网页路由
├── internal/config/               YAML 配置模型
├── internal/database/             SQLite、迁移和完整性检查
├── internal/media/voice/          Opus 语音 SFU
├── internal/media/rtmp/           RTMP 发布接入
├── internal/media/stream/         活跃流注册和分发
├── internal/media/flv/            HTTP-FLV 封装
├── internal/media/audiotranscode/ AAC 到 Opus 的共享低延迟转码
├── internal/media/rtcplay/        浏览器 WebRTC 播放
├── internal/media/turnserver/     内建 STUN/TURN
├── internal/network/publicip/     公网 IPv4 自动发现和运行时状态
├── internal/repository/           数据访问层
├── internal/wg/                   WireGuard 协调
├── internal/ws/                   应用事件与媒体信令
├── pkg/                            JWT 和响应工具
└── web/                            编译进二进制的网页资源
```

## 本地开发

```powershell
cd server
Copy-Item ..\deployment\templates\server.yaml.template config.yaml
# 替换所有占位符和 DATA_DIR
go test ./...
go vet ./...
go run ./cmd/server
```

服务从当前工作目录读取 `config.yaml`。开发配置、JWT 密钥、管理员令牌、TURN 凭据和生产数据不得提交到 Git。

服务端默认允许合法但未登记的 Stream Key 作为网页临时直播。它只在推流活跃期间显示于网页直播大厅，不会创建数据库记录或加入客户端房间列表；需要严格限制为正式房间入口时，可以将 `media.rtmp.allow_temporary_streams` 设为 `false` 并重启服务。

浏览器播放优先使用 WebRTC。H.264 不转码，AAC 由每路活动源共享的 FFmpeg 工作进程转为 Opus，再把视频和音频 RTP 发给所有观看者。网页默认不静音；浏览器阻止有声自动播放时等待用户交互。WebRTC 协商、连接、视频首帧或预期音频轨道失败后，本次页面播放会话锁定 HTTP-FLV；FLV 断线只重连 FLV，不会重新进入 WebRTC/FLV 循环。播放引擎会根据 SPS 匹配常见的 H.264 Baseline、Main 和 High Profile。

`media.public_ip` 是手动 IPv4 覆盖值。留空时，服务端先检查本机公网 IPv4，再通过 `media.public_ip_discovery.stun_servers` 自动探测，并按配置周期刷新。语音、浏览器播放和 TURN 的新会话读取当前地址，不需要重启 NexusRoom。这个能力不启用 IPv6，也不会代替路由器和 Docker 的 UDP 端口映射。

`media.rtc.ffmpeg_path` 默认是 `ffmpeg`。路径无效或转码进程退出时，原始 AAC 仍可供 HTTP-FLV 使用，但带音频源的浏览器 WebRTC 协商会失败并触发网页回退。

## 数据库

服务端使用 GORM 和 SQLite。连接启用 WAL、外键、5 秒 busy timeout 和 `NORMAL` 同步模式；启动时执行 AutoMigrate、`PRAGMA integrity_check` 和外键检查。生产备份至少包含数据库主文件、WAL、SHM、上传目录和 WireGuard 私钥。

## 生命周期

启动顺序为配置、数据库、仓库、WireGuard、TURN、语音 SFU、WebSocket Hub、流注册表、浏览器播放引擎、RTMP、HTTP 和消息清理任务。收到 `SIGINT` 或 `SIGTERM` 后停止接收新连接，关闭 RTMP 和 HTTP，并在超时内释放媒体与数据库资源。

## 验证

服务端改动至少执行：

```powershell
go test ./...
go vet ./...
go build ./cmd/server
```

媒体、网络或部署改动还需要执行两客户端语音、OBS 推流、HTTP-FLV、浏览器 WebRTC、TURN 中继、WireGuard 和进程重启持久化验收。
