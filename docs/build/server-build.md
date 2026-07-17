# 服务端编译、Docker 构建与打包

NexusRoom 服务端是单一 Go 应用。SQLite、REST、WebSocket、语音 SFU、RTMP、HTTP-FLV、WebRTC 播放、TURN、网页资源和 WireGuard 协调模块均由同一个二进制及同一个 Docker 容器提供。

本文适用于 `2.1.0`。

## 1. 构建要求

直接编译需要：

- Go 1.25 或更高版本
- 支持 CGO 的 C 编译器，因为 SQLite 驱动使用 CGO
- Linux 生产环境需要 WireGuard tools、iproute2 和 iptables
- Docker 构建需要 Docker Engine 及 Compose v2

检查工具：

```bash
go version
gcc --version
docker version
docker compose version
```

## 2. 服务端质量检查

```bash
cd server
go mod download
go vet ./...
go test ./...
```

## 3. 直接编译二进制

Linux Release：

```bash
cd server
CGO_ENABLED=1 \
CGO_CFLAGS='-D_LARGEFILE64_SOURCE -D_GNU_SOURCE' \
GOOS=linux go build \
  -trimpath \
  -ldflags='-s -w' \
  -o nexusroom \
  ./cmd/server
```

也可以使用仓库脚本：

```bash
cd deployment
chmod +x scripts/*.sh
./scripts/build-direct.sh
```

脚本输出到：

```text
deployment/data/bin/nexusroom
```

Windows 开发构建：

```powershell
cd server
$env:CGO_ENABLED = '1'
go build -trimpath -ldflags='-s -w' -o nexusroom-server.exe ./cmd/server
```

Windows 构建需要可用的 GCC，例如 MSYS2/MinGW。生产部署推荐 Linux。

Alpine/musl 和部分 Linux 工具链需要显式启用 large-file/GNU 接口，否则 `go-sqlite3` 可能无法识别 `pread64`、`pwrite64` 和 `off64_t`。仓库 Dockerfile 与直接构建脚本已经包含对应的 `CGO_CFLAGS`。

## 4. 本地运行配置

复制配置模板：

```bash
cp deployment/templates/server.yaml.template server/config.yaml
```

至少替换：

- `YOUR_IP`
- `DATA_DIR`
- `CHANGE_ME_JWT`
- `CHANGE_ME_ADMIN`
- `CHANGE_ME_TURN_USER`
- `CHANGE_ME_TURN_PASSWORD`

直接运行时，`DATA_DIR` 必须是当前用户可写目录。生产配置包含密钥，不提交到 Git。

启动：

```bash
cd server
./nexusroom
```

检查：

```bash
curl http://127.0.0.1:8080/ping
```

## 5. 构建单 Docker 镜像

在仓库根目录执行：

```bash
docker build \
  -t nexusroom-server:latest \
  ./server
```

网络受限时可指定 Go 模块代理：

```bash
docker build \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -t nexusroom-server:latest \
  ./server
```

检查镜像：

```bash
docker image inspect nexusroom-server:latest
```

该镜像只包含 NexusRoom 二进制及运行 WireGuard 所需工具，不包含 PostgreSQL、Redis、LiveKit、SRS 或 nginx 服务。

## 6. 使用 Docker Compose 构建并启动

推荐在 Linux 服务器执行：

```bash
cd deployment
chmod +x scripts/*.sh
export NEXUSROOM_PUBLIC_IP='服务器公网IP'
./scripts/install.sh
```

安装脚本会生成私有配置、创建持久化目录、构建本地源码并启动一个 `nexusroom` 容器。

手动执行 Compose：

```bash
cd deployment
docker compose config
docker compose build nexusroom
docker compose up -d nexusroom
docker compose logs -f nexusroom
```

Compose 挂载：

```text
deployment/config/server.yaml -> /app/config.yaml
deployment/data/              -> /app/data/
```

SQLite 数据、上传文件和 WireGuard 私钥均位于持久化数据目录，不应写入镜像层。

## 7. 跨架构镜像

构建 Linux AMD64：

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t nexusroom-server:latest \
  ./server
```

构建 Linux ARM64：

```bash
docker buildx build \
  --platform linux/arm64 \
  --load \
  -t nexusroom-server:arm64 \
  ./server
```

构建并推送多架构镜像：

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t REGISTRY/NAMESPACE/nexusroom-server:2.1.0 \
  ./server
```

## 8. 离线镜像打包

导出：

```bash
docker save \
  -o nexusroom-server-latest.tar \
  nexusroom-server:latest
sha256sum nexusroom-server-latest.tar > nexusroom-server-latest.tar.sha256
```

目标服务器校验并导入：

```bash
sha256sum -c nexusroom-server-latest.tar.sha256
docker load -i nexusroom-server-latest.tar
cd deployment
docker compose up -d --no-build
```

镜像归档属于发布产物，已被 Git 忽略，不要提交到源码仓库。

## 9. 网络和运行权限

生产服务器需要开放：

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| 8080 | TCP | REST、WebSocket、网页和 HTTP-FLV |
| 1935 | TCP | RTMP 推流 |
| 3478 | UDP | STUN/TURN |
| 50000-50050 | UDP | WebRTC 直连媒体 |
| 51000-51100 | UDP | TURN Relay |
| 51820 | UDP | WireGuard |

容器需要 `NET_ADMIN`、`/dev/net/tun` 和 IPv4 转发。Docker Desktop 可以用于构建镜像，但完整 WireGuard 与公网媒体验收应在 Linux 主机进行。

## 10. 发布前检查

```bash
cd server
go vet ./...
go test ./...

cd ../deployment
docker compose config
```

启动后至少检查：

```bash
curl http://127.0.0.1:8080/ping
docker compose ps
docker compose logs --tail=200 nexusroom
```

还应使用真实客户端完成登录、双端语音、RTMP 推流、HTTP-FLV 播放、TURN 中继和 WireGuard VLAN 验收。

## 11. 清理产物

删除直接编译的本地二进制即可；不要删除持久化数据：

```bash
rm -f server/nexusroom server/nexusroom-server
```

Docker 清理应按镜像标签明确执行。`deployment/data/`、`deployment/config/server.yaml` 包含运行数据或密钥，不属于构建缓存。
