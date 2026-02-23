# NexusRoom 部署文档

## 系统要求

### 服务器配置建议

| 规模 | CPU | 内存 | 存储 | 带宽 |
|------|-----|------|------|------|
| 小型（< 50人） | 2核 | 4GB | 50GB SSD | 10Mbps |
| 中型（50-200人） | 4核 | 8GB | 100GB SSD | 50Mbps |
| 大型（200+人） | 8核+ | 16GB+ | 200GB+ SSD | 100Mbps+ |

### 操作系统

- Ubuntu 20.04/22.04 LTS
- Debian 11/12
- CentOS 8 / Rocky Linux 8
- 其他支持 Docker 的 Linux 发行版

### 必需软件

- Docker 20.10+
- Docker Compose 2.0+

## 端口说明

| 端口 | 协议 | 服务 | 说明 |
|------|------|------|------|
| 8080 | TCP | Golang 主服务 | REST API + WebSocket |
| 1935 | TCP | LiveKit Ingress | RTMP 推流接收（OBS） |
| 7880 | TCP | LiveKit | WebRTC 信令 |
| 50000-50050 | UDP | LiveKit | WebRTC 媒体流 |
| 51820 | UDP | WireGuard | VLAN 虚拟局域网 |
| 3000 | TCP | Web 管理后台 | 可选，仅管理员访问 |

## 快速部署

### 1. 安装 Docker

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# 验证安装
docker --version
docker compose version
```

### 2. 下载部署文件

```bash
# 克隆仓库或下载部署包
git clone https://github.com/yourusername/nexusroom.git
cd nexusroom/deploy

# 或者下载并解压
wget https://github.com/yourusername/nexusroom/releases/download/v1.3.1/deploy.tar.gz
tar -xzf deploy.tar.gz
cd deploy
```

### 3. 运行部署脚本

```bash
chmod +x deploy.sh
./deploy.sh
```

脚本会自动：
- 检查 Docker 环境
- 生成随机密码和密钥
- 创建配置文件
- 拉取镜像并启动服务

### 4. 配置防火墙

```bash
# UFW (Ubuntu)
sudo ufw allow 8080/tcp
sudo ufw allow 1935/tcp
sudo ufw allow 7880/tcp
sudo ufw allow 50000:50050/udp
sudo ufw allow 51820/udp
sudo ufw allow 3000/tcp  # 可选
sudo ufw reload

# 或者使用 iptables
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 1935 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 7880 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 50000:50050 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT
```

### 5. 云服务器安全组配置

如果使用阿里云、腾讯云等云服务，需要在控制台配置安全组：

| 方向 | 协议 | 端口范围 | 授权对象 |
|------|------|---------|---------|
| 入方向 | TCP | 8080 | 0.0.0.0/0 |
| 入方向 | TCP | 1935 | 0.0.0.0/0 |
| 入方向 | TCP | 7880 | 0.0.0.0/0 |
| 入方向 | UDP | 50000/50050 | 0.0.0.0/0 |
| 入方向 | UDP | 51820 | 0.0.0.0/0 |

## 手动部署

### 1. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env` 文件：

```bash
# 数据库密码（必填）
DB_PASSWORD=your-secure-password

# LiveKit API 密钥
LIVEKIT_API_KEY=your-livekit-key
LIVEKIT_API_SECRET=your-livekit-secret
```

### 2. 配置服务端

```bash
# 生成 config.yaml
cp config.yaml.template config.yaml

# 编辑配置文件
nano config.yaml
```

关键配置项：

```yaml
server:
  port: 8080
  mode: release

database:
  password: "your-db-password"  # 与 .env 中的 DB_PASSWORD 一致

auth:
  jwt_secret: "your-jwt-secret" # 至少32位随机字符串
  admin_token: ""               # 初始超管注册令牌（可选）

livekit:
  api_key: "your-livekit-key"       # 与 .env 一致
  api_secret: "your-livekit-secret" # 与 .env 一致

wireguard:
  server_ip: "your-server-public-ip"  # 服务器公网IP
  subnet: "10.0.8.0/24"              # VLAN 网段
```

### 3. 配置 LiveKit

编辑 `livekit.yaml`：

```yaml
api_key: your-livekit-key
api_secret: your-livekit-secret
```

### 4. 启动服务

```bash
# 创建数据目录
mkdir -p data/uploads

# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 查看服务状态
docker-compose ps
```

## HTTPS 配置

### 使用 Nginx 反向代理 + Let's Encrypt

#### 1. 安装 Nginx 和 Certbot

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
```

#### 2. 配置 Nginx

创建 `/etc/nginx/sites-available/nexusroom`：

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # 主服务 API
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # WebSocket
    location /ws {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    # LiveKit
    location /livekit/ {
        proxy_pass http://localhost:7880/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

启用配置：

```bash
sudo ln -s /etc/nginx/sites-available/nexusroom /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

#### 3. 获取 SSL 证书

```bash
sudo certbot --nginx -d your-domain.com
```

#### 4. 更新服务端配置

编辑 `config.yaml`：

```yaml
server:
  domain: "your-domain.com"  # 配置域名后自动启用 HTTPS
```

重启服务：

```bash
docker-compose restart server
```

## 备份与恢复

### 备份数据

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/backup/nexusroom"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# 备份 PostgreSQL
docker exec nexusroom-postgres pg_dump -U nexusroom nexusroom > $BACKUP_DIR/db_$DATE.sql

# 备份上传文件
tar -czf $BACKUP_DIR/uploads_$DATE.tar.gz ./data/uploads

# 备份配置文件
cp config.yaml $BACKUP_DIR/config_$DATE.yaml
cp .env $BACKUP_DIR/env_$DATE

echo "Backup completed: $BACKUP_DIR/*_$DATE"
```

### 恢复数据

```bash
#!/bin/bash
# restore.sh

BACKUP_DATE=$1  # 传入备份日期，如 20240101_120000

# 恢复数据库
docker exec -i nexusroom-postgres psql -U nexusroom nexusroom < backup/db_$BACKUP_DATE.sql

# 恢复上传文件
tar -xzf backup/uploads_$BACKUP_DATE.tar.gz

# 恢复配置
cp backup/config_$BACKUP_DATE.yaml config.yaml
cp backup/env_$BACKUP_DATE .env

# 重启服务
docker-compose restart
```

## 监控与日志

### 查看服务日志

```bash
# 所有服务
docker-compose logs -f

# 特定服务
docker-compose logs -f server
docker-compose logs -f livekit

# 最近100行
docker-compose logs --tail=100 server
```

### 日志轮转

创建 `/etc/logrotate.d/nexusroom`：

```
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
}
```

### 资源监控

```bash
# 查看容器资源使用
docker stats

# 查看系统资源
df -h
free -h
```

## 升级

### 更新到最新版本

```bash
# 进入部署目录
cd nexusroom/deploy

# 拉取最新镜像
docker-compose pull

# 重新启动服务
docker-compose up -d

# 清理旧镜像
docker image prune -f
```

### 数据库迁移

```bash
# 进入 server 容器
docker exec -it nexusroom-server sh

# 执行迁移（如果有）
# go run migrations/migrate.go
```

## 故障排查

### 服务无法启动

```bash
# 检查日志
docker-compose logs server

# 检查端口占用
sudo lsof -i :8080
sudo lsof -i :1935

# 检查配置
docker-compose config
```

### 数据库连接失败

```bash
# 检查 PostgreSQL 状态
docker-compose ps postgres
docker-compose logs postgres

# 测试连接
docker exec -it nexusroom-postgres psql -U nexusroom -d nexusroom -c "SELECT 1"
```

### WebRTC 连接问题

```bash
# 检查 LiveKit 状态
docker-compose logs livekit

# 检查 UDP 端口
curl http://localhost:7880

# 测试 WebRTC
# 访问 https://your-domain.com:7880 查看 LiveKit 状态
```

### VLAN 无法连接

```bash
# 检查 WireGuard 模块
lsmod | grep wireguard

# 检查端口
sudo ss -ulnp | grep 51820

# 检查容器权限
docker inspect nexusroom-server | grep CapAdd
```

## 安全加固

### 1. 修改默认密钥

```bash
# 生成随机密钥
openssl rand -hex 32

# 更新 config.yaml
nano config.yaml
```

### 2. 限制管理后台访问

在 Nginx 配置中添加：

```nginx
location /admin {
    allow 192.168.1.0/24;  # 仅允许内网访问
    deny all;
    proxy_pass http://localhost:3000;
}
```

### 3. 启用 Fail2ban

```bash
sudo apt install fail2ban

# 创建 /etc/fail2ban/jail.local
[nexusroom]
enabled = true
port = 8080
filter = nexusroom
logpath = /var/log/nexusroom.log
maxretry = 5
bantime = 3600
```

## 卸载

```bash
# 停止并删除容器
docker-compose down -v

# 删除镜像
docker rmi nexusroom-server:latest

# 删除数据（谨慎操作！）
rm -rf ./data
rm -f config.yaml .env
```

## 获取帮助

- GitHub Issues: https://github.com/yourusername/nexusroom/issues
- 文档: https://docs.nexusroom.io
- 社区: https://discord.gg/nexusroom
