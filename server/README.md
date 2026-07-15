# Server

本目录只存放 NexusRoom Go 主服务源码。PostgreSQL、Redis、LiveKit、SRS 和正式运行配置统一由 `../deployment/` 管理。

## 开发检查

```bash
go test ./...
go build ./cmd/server
```

服务启动时从当前工作目录读取 `config.yaml`。本地直接运行前，可基于 `../deployment/templates/server.yaml.template` 创建仅供本机使用的 `server/config.yaml`，并准备对应的 PostgreSQL、Redis、LiveKit 和 SRS 服务。

正式部署请不要在本目录保存生产配置，使用 [deployment](../deployment/README.md)。
