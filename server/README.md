# Server

[完整的服务端编译、Docker 构建与打包文档](../docs/build/server-build.md)

此目录包含 NexusRoom 单体 Go 服务端源码。服务启动时从当前工作目录读取 `config.yaml`，使用 SQLite 文件持久化数据，并在同一进程内运行 HTTP、WebSocket、语音 SFU、RTMP、FLV、WebRTC 播放、TURN 和 WireGuard 协调模块。

## 开发检查

```bash
go test ./...
go build ./cmd/server
```

本地配置可从 `../deployment/templates/server.yaml.template` 复制。需要替换所有占位符，并将 `DATA_DIR` 改为本机可写目录。

主要源码区域：

```text
cmd/server/             进程装配和生命周期
internal/api/           REST 与网页路由
internal/database/      SQLite 打开、迁移和完整性检查
internal/media/voice/   Opus 语音 SFU
internal/media/rtmp/    RTMP 接入
internal/media/stream/  活跃流注册和分发
internal/media/flv/     HTTP-FLV 封装
internal/media/rtcplay/ 浏览器 WebRTC 播放
internal/media/turnserver/ 内建 TURN
internal/ws/            应用与媒体信令
web/                    编译进二进制的网页资源
```

生产环境请使用 [deployment](../deployment/README.md) 中的 Docker 或直接部署方案，不要在源码目录保存生产配置和数据。
