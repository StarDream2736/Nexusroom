# NexusRoom 服务端编译文档

## 环境要求

- **Go**: 1.22 或更高版本
- **PostgreSQL**: 16.x
- **Redis**: 7.x
- **Docker & Docker Compose**: （可选，用于容器化部署）

## 目录结构

```
server/
├── cmd/
│   └── server/
│       └── main.go            # 程序入口
├── internal/
│   ├── api/                   # HTTP REST API 路由
│   │   ├── handler/           # 各业务 Handler
│   │   ├── middleware/        # Auth / CORS / RateLimit
│   │   └── router.go          # 路由注册
│   ├── ws/                    # WebSocket 处理
│   │   ├── hub.go             # 连接中心 (Hub)
│   │   ├── client.go          # 单个客户端连接
│   │   └── message.go         # 消息类型定义
│   ├── model/                 # 数据库模型 (GORM)
│   ├── service/               # 业务逻辑层
│   ├── repository/            # 数据访问层
│   ├── wg/                    # WireGuard 协调服务
│   │   ├── coordinator.go     # 密钥分发 & IP 分配
│   │   └── peer.go            # Peer 状态管理
│   └── config/
│       └── config.go          # 配置加载
├── pkg/                       # 可复用公共包
│   ├── jwt/                   # JWT 工具
│   └── util/                  # 通用工具
├── migrations/                # 数据库迁移文件
├── Dockerfile                 # Docker 构建文件
├── go.mod                     # Go 模块定义
├── go.sum                     # Go 依赖锁定
└── config.yaml                # 服务端配置文件
```

## 本地开发编译

### 1. 克隆代码

```bash
cd nexusroom/server
```

### 2. 安装依赖

```bash
go mod download
```

### 3. 配置环境

复制配置文件模板并修改：

```bash
cp config.yaml config.yaml.local
```

编辑 `config.yaml.local`，修改以下配置：

```yaml
database:
  host: localhost           # 本地开发使用 localhost
  port: 5432
  name: nexusroom
  user: nexusroom
  password: "your-password" # 修改为你的数据库密码

auth:
  jwt_secret: "your-secret" # 至少32位随机字符串
```

### 4. 启动依赖服务

使用 Docker 启动 PostgreSQL 和 Redis：

```bash
docker run -d \
  --name nexusroom-postgres \
  -e POSTGRES_DB=nexusroom \
  -e POSTGRES_USER=nexusroom \
  -e POSTGRES_PASSWORD=your-password \
  -p 5432:5432 \
  postgres:16-alpine

docker run -d \
  --name nexusroom-redis \
  -p 6379:6379 \
  redis:7-alpine
```

### 5. 编译运行

```bash
# 开发模式（带热重载，需安装 air）
go install github.com/cosmtrek/air@latest
air

# 或直接运行
go run cmd/server/main.go

# 编译二进制
go build -o nexusroom-server cmd/server/main.go
./nexusroom-server
```

服务启动后，访问 http://localhost:8080/ping 验证。

## Docker 编译

### 1. 构建镜像

```bash
docker build -t nexusroom-server:latest .
```

### 2. 运行容器

```bash
docker run -d \
  --name nexusroom-server \
  -p 8080:8080 \
  -p 51820:51820/udp \
  -v $(pwd)/config.yaml:/app/config.yaml \
  -v $(pwd)/data:/app/data \
  --cap-add NET_ADMIN \
  nexusroom-server:latest
```

## 生产环境构建

### 交叉编译

```bash
# Linux AMD64
GOOS=linux GOARCH=amd64 go build -o nexusroom-server-linux-amd64 cmd/server/main.go

# Linux ARM64
GOOS=linux GOARCH=arm64 go build -o nexusroom-server-linux-arm64 cmd/server/main.go

# Windows AMD64
GOOS=windows GOARCH=amd64 go build -o nexusroom-server-windows-amd64.exe cmd/server/main.go

# macOS AMD64
GOOS=darwin GOARCH=amd64 go build -o nexusroom-server-darwin-amd64 cmd/server/main.go

# macOS ARM64 (M1/M2)
GOOS=darwin GOARCH=arm64 go build -o nexusroom-server-darwin-arm64 cmd/server/main.go
```

### 优化构建（减小体积）

```bash
# 使用 -ldflags 去除调试信息
GOOS=linux GOARCH=amd64 go build \
  -ldflags "-s -w" \
  -o nexusroom-server cmd/server/main.go

# 使用 upx 进一步压缩（可选）
upx --best nexusroom-server
```

## 测试

### 运行单元测试

```bash
go test ./...
```

### 运行测试并生成覆盖率报告

```bash
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

### 代码检查

```bash
# 安装 golangci-lint
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# 运行检查
golangci-lint run
```

## 常见问题

### 1. 依赖下载失败

```bash
# 设置 GOPROXY
go env -w GOPROXY=https://goproxy.cn,direct

# 重新下载依赖
go mod download
```

### 2. 数据库连接失败

- 检查 PostgreSQL 是否启动
- 检查 config.yaml 中的数据库配置
- 确认数据库用户和权限正确

### 3. 端口被占用

```bash
# 查找占用 8080 端口的进程
lsof -i :8080

# 终止进程
kill -9 <PID>
```

### 4. WireGuard 权限问题

Docker 运行时需要添加 `--cap-add NET_ADMIN` 参数。

## API 测试

### 使用 curl 测试

```bash
# 健康检查
curl http://localhost:8080/ping

# 注册用户
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "testpass123",
    "nickname": "Test User"
  }'

# 登录
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "testpass123"
  }'
```

## 性能优化

### 1. 数据库连接池

在 `main.go` 中配置 GORM 连接池：

```go
sqlDB, err := db.DB()
sqlDB.SetMaxOpenConns(100)
sqlDB.SetMaxIdleConns(10)
sqlDB.SetConnMaxLifetime(time.Hour)
```

### 2. 日志级别

生产环境设置 `mode: release` 以减少日志输出。

### 3. 编译优化

使用 `-ldflags "-s -w"` 去除符号表和调试信息。

## 安全建议

1. **修改默认密钥**: 生产环境必须修改 `jwt_secret` 和 `livekit` 的密钥
2. **使用 HTTPS**: 配置 `domain` 字段启用 HTTPS
3. **防火墙配置**: 仅开放必要端口
4. **定期备份**: 定期备份 PostgreSQL 数据
