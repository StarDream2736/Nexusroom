# Deployment

本目录只负责安装和运行 NexusRoom 服务端栈，不存放客户端或服务端业务源码。

## 目录

```text
deployment/
├── docker-compose.yml
├── scripts/install.sh
├── templates/              # server、LiveKit、SRS 配置模板
├── config/                 # 安装后生成的运行配置
├── data/                   # 服务运行数据
└── web-admin/              # 可选 Web 管理后台静态文件
```

`config/server.yaml`、`config/livekit.yaml`、`config/srs.conf`、`.env` 和 `data/` 均为本机运行状态，已被 Git 忽略。`config/nginx.conf` 是可提交的静态配置。

## 一键安装

```bash
cd deployment
chmod +x scripts/install.sh
./scripts/install.sh
```

脚本可以从仓库任意工作目录调用，并兼容 `docker compose` 与旧版 `docker-compose`。

已有本地配置在本次目录整理中已迁移到 `config/`，安装脚本不会覆盖已有文件。
