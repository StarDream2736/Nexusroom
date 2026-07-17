# 2026-07-15 开发环境与目录结构整理

## 工作目标

将客户端、服务端、安装部署和文档明确分区，避免客户端工具、生产配置、安装脚本和业务源码混放。`docx/` 继续作为日志归档目录，不参与程序构建。

## 调整后的结构

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
│   ├── systemd/
│   ├── templates/
│   ├── config/
│   ├── data/
│   └── docker-compose.yml
├── docs/
│   └── development/
└── docx/
```

具体移动内容：

| 原位置 | 新位置 | 说明 |
| --- | --- | --- |
| `wg-helper/` | `client/native/wg-helper/` | Windows 客户端原生依赖 |
| `tools/ffmpeg.exe` | `client/tools/ffmpeg.exe` | 客户端屏幕捕获和推流工具 |
| `deploy/` | `deployment/` | 部署内容与业务源码分离 |
| 安装脚本 | `deployment/scripts/` | Docker 与直接部署分别维护 |
| 可提交配置 | `deployment/templates/` | 只保留当前服务端模板 |
| 生成配置 | `deployment/config/` | 本机敏感配置，不提交 Git |
| 运行数据 | `deployment/data/` | SQLite、上传文件和构建产物 |

## 后续单体化调整

同一天完成的服务端单体化改造进一步简化了部署区域：旧 LiveKit、SRS 和 nginx 模板已删除，Docker Compose 只运行一个 NexusRoom 容器，并新增直接 Linux/systemd 部署。完整记录见 [服务端能力内建与单体化改造](2026-07-15-unified-server.md)。

## 文档与 UI 约定

- 根 README 和各区域 README 已按当前结构重写。
- 非 UI 维护文本中的 emoji 已移除。
- UI 规范和界面中承担在线、离线及说话状态表达的 emoji 和图标继续保留。

## 验证

- Go 服务端测试通过。
- Flutter 静态分析无 error。
- 生成配置、运行数据、本地二进制和 SDK 缓存均由 Git 忽略。
