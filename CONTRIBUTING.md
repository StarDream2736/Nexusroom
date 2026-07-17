# 贡献指南

感谢参与 NexusRoom。提交代码前请先搜索现有 Issue，较大改动应先创建 Issue 说明目标、兼容性和测试方式。

## 开发流程

1. 从最新 `main` 创建独立分支。
2. 只提交与当前问题相关的源码、测试和公开文档，不提交配置、密钥、日志、数据库或构建产物。
3. 客户端改动运行 `flutter analyze`、`flutter test`；数据模型改动先运行 `dart run build_runner build --delete-conflicting-outputs`。
4. 服务端改动运行 `go vet ./...`、`go test ./...`。
5. 部署改动运行 `docker compose config --quiet`。
6. Pull Request 说明行为变化、验证结果、兼容性和必要的迁移步骤。

## 代码与提交

- 保持 `client/`、`server/`、`deployment/` 和 `docs/` 的边界。
- UI 保留标题栏、左侧导航、中央内容区和房间右侧信息栏，不使用 emoji 表达状态。
- 新增持久化字段必须提供迁移和隔离测试。
- 提交信息使用简短祈使句，例如 `fix: isolate message cache by account`。
- 版本遵循语义版本：破坏兼容提升主版本，新增兼容功能提升次版本，兼容修复提升补丁版本。

提交即表示你有权贡献相关内容，并同意贡献按仓库 MIT License 发布。
