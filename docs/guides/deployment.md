# 安装与部署指南

NexusRoom `2.1.0` 服务端采用单进程、单容器架构。完整配置、端口和运行规范见 [NexusRoom 技术规范](../NexusRoom.md)，镜像与二进制构建见 [服务端编译与打包](../build/server-build.md)。

## Docker 部署

```bash
cd deployment
chmod +x scripts/*.sh
./scripts/install.sh
```

安装脚本生成 `config/server.yaml`，将状态持久化到 `deployment/data/`，从本地 `server/` 源码构建镜像，并启动一个 `nexusroom` 容器。

宿主机 8080 端口冲突时，在 `deployment/.env` 中设置：

```dotenv
NEXUSROOM_HTTP_PORT=18080
```

TURN 中继映射变量 `NEXUSROOM_TURN_RELAY_PORT_RANGE` 必须与 `server.yaml` 中的 `media.turn.relay_port_min` 和 `relay_port_max` 完全一致。

## Linux 直接部署

安装 Go 1.25 或更高版本、GCC、WireGuard tools、iproute2 和 iptables，然后执行：

```bash
cd deployment
chmod +x scripts/*.sh
sudo ./scripts/install-direct.sh
```

脚本构建同一份源码，将二进制安装到 `/usr/local/bin/nexusroom`，配置写入 `/etc/nexusroom/config.yaml`，状态写入 `/var/lib/nexusroom`，并启用 `nexusroom.service`。

## 必需端口

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| 8080 | TCP | API、WebSocket、内嵌网页和 HTTP-FLV |
| 1935 | TCP | RTMP 推流接入 |
| 3478 | UDP | STUN/TURN |
| 50000-50050 | UDP | WebRTC 直连媒体 |
| 51000-51100 | UDP | TURN 中继 |
| 51820 | UDP | WireGuard |

## 数据与安全

- `config/server.yaml` 包含 JWT、管理员和 TURN 凭据，必须限制读取权限。
- 生产环境必须替换模板中的所有 `CHANGE_ME`、`YOUR_IP` 和 `DATA_DIR`。
- 定期备份 `data/nexusroom.db`、WAL/SHM、`data/uploads/` 和 WireGuard 私钥。
- HTTP 与 WebSocket 应在外部 TLS 入口后提供服务；UDP 媒体和 WireGuard 端口必须直接正确映射。
- Docker 运行 WireGuard 需要 `NET_ADMIN`、`/dev/net/tun` 和相应 sysctl。

## 常用检查

```bash
docker compose config --quiet
docker compose ps
docker compose logs --tail=200 nexusroom
curl http://127.0.0.1:8080/ping
```

健康检查应返回业务码 `20000`、状态 `ok` 和当前服务端版本。
