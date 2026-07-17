# 服务端开发指南

本文档说明 NexusRoom `2.1.0` 单体 Go 服务端。完整系统设计见 [NexusRoom 技术规范](../NexusRoom.md)，构建发布见 [服务端编译与打包](../build/server-build.md)。

## 运行边界

服务端是单一 Go 进程，同时提供 REST API、WebSocket、SQLite、Opus 语音 SFU、RTMP 接入、HTTP-FLV、浏览器 WebRTC 播放、STUN/TURN、WireGuard 协调和内嵌网页。运行时不依赖 PostgreSQL、Redis、LiveKit Server、SRS 或 nginx。

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
├── internal/media/rtcplay/        浏览器 WebRTC 播放
├── internal/media/turnserver/     内建 STUN/TURN
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
