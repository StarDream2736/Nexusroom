# 2026-07-15 开发环境与目录结构整理

## 工作目标

将客户端、服务端、安装部署和文档从仓库根目录开始明确分区，避免客户端专用工具、生产配置、安装脚本和业务源码混放。

## 目录调整

调整后的仓库结构：

```text
Nexusroom/
├── client/
│   ├── lib/
│   ├── native/wg-helper/
│   ├── tools/
│   ├── test/
│   └── windows/
├── server/
│   ├── cmd/
│   ├── internal/
│   ├── pkg/
│   └── web/
├── deployment/
│   ├── scripts/
│   ├── templates/
│   ├── config/
│   ├── data/
│   └── docker-compose.yml
└── docs/
    ├── development/
    ├── NexusRoom.md
    └── README.md
```

具体移动内容：

| 原位置 | 新位置 | 说明 |
| --- | --- | --- |
| `wg-helper/` | `client/native/wg-helper/` | WireGuard helper 是 Windows 客户端的原生依赖 |
| `tools/ffmpeg.exe` | `client/tools/ffmpeg.exe` | FFmpeg 仅由客户端屏幕捕获和打包流程使用 |
| `deploy/` | `deployment/` | 安装部署与业务源码分离 |
| `deploy/deploy.sh` | `deployment/scripts/install.sh` | 安装脚本与配置模板分离 |
| 部署配置模板 | `deployment/templates/` | 只保存可提交的模板 |
| 生成配置 | `deployment/config/` | 保存本机和生产运行配置，敏感文件由 Git 忽略 |

## 构建与部署调整

- 更新 Windows CMake 路径，使发布构建从 `client/native/wg-helper/` 和 `client/tools/` 收集依赖。
- Docker Compose 挂载统一指向 `deployment/config/`。
- 安装脚本使用自身路径定位部署根目录，不再要求调用者预先切换到固定工作目录。
- 安装脚本同时支持 `docker compose` 与旧版 `docker-compose`。
- SRS 配置改为从 `templates/srs.conf.template` 生成，并在首次安装时写入服务器公网 IP。
- 原有 `.env`、服务端配置、LiveKit 配置、SRS 配置和数据目录均已迁移保留，安装脚本不会覆盖已有配置。

## 文档调整

- 根 README 更新项目结构、快速部署路径和组件入口。
- 新增 `client/README.md`、`server/README.md`、`deployment/README.md` 与 `docs/README.md`。
- 技术文档中的旧 `deploy/`、根级 `wg-helper/` 和根级 `tools/` 路径已更新。
- 非 UI 维护文本中的 Emoji 已移除，改用明确的纯文本状态词；UI 规范和示意图中承担在线、离线及说话状态表达的图标继续保留。

## 验证结果

| 验证项 | 结果 |
| --- | --- |
| `go test ./...`，服务端 | 通过；当前模块没有单元测试文件，完成编译检查 |
| `go test ./...`，WireGuard helper | 通过；当前模块没有单元测试文件，完成编译检查 |
| `docker compose config --quiet` | 通过 |
| `flutter build windows --release` | 通过 |
| Windows 发布目录依赖 | 已包含 `nexusroom-wg.exe`、`wintun.dll` 和 `ffmpeg.exe` |
| Git 忽略规则 | 已确认 `.env`、生成配置、运行数据和 FFmpeg 本地二进制不会被提交 |

本次工作只调整工程结构、构建路径、部署组织和文档，没有修改业务协议、数据库模型或 API 行为。
