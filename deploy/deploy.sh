#!/bin/bash
# NexusRoom Server 部署脚本
set -e

echo '🚀 NexusRoom Server 部署脚本'

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo '❌ 错误: 请先安装 Docker'
    echo '   安装指南: https://docs.docker.com/get-docker/'
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo '❌ 错误: 请先安装 Docker Compose'
    echo '   安装指南: https://docs.docker.com/compose/install/'
    exit 1
fi

# 检查 .env 文件
if [ ! -f .env ]; then
    echo '📝 创建 .env 文件...'
    cat > .env << EOF
# 数据库密码（请修改）
DB_PASSWORD=$(openssl rand -hex 16)

# LiveKit API 密钥（请修改）
LIVEKIT_API_KEY=your-livekit-key
LIVEKIT_API_SECRET=$(openssl rand -hex 32)
EOF
    echo '✅ .env 文件已创建，请编辑修改密码和密钥'
fi

# 生成 config.yaml（如果不存在）
if [ ! -f config.yaml ]; then
    echo '📝 生成 config.yaml...'
    
    # 读取 .env 变量
    source .env
    
    # 生成 JWT Secret
    JWT_SECRET=$(openssl rand -hex 32)
    
    # 获取服务器公网 IP
    echo '🌐 正在检测服务器公网 IP...'
    SERVER_IP=$(curl -s https://api.ipify.org || echo "your-server-ip")
    echo "   检测到的 IP: $SERVER_IP"
    
    cat > config.yaml << EOF
# NexusRoom Server Configuration

server:
  port: 8080
  mode: release
  domain: ""

database:
  host: postgres
  port: 5432
  name: nexusroom
  user: nexusroom
  password: "$DB_PASSWORD"

redis:
  host: redis
  port: 6379
  password: ""

auth:
  jwt_secret: "$JWT_SECRET"
  jwt_expire_hours: 720
  admin_token: ""

message:
  retention_days: 30

livekit:
  url: ws://livekit:7880
  api_key: "$LIVEKIT_API_KEY"
  api_secret: "$LIVEKIT_API_SECRET"

livekit_ingress:
  rtmp_port: 1935

wireguard:
  server_ip: "$SERVER_IP"
  listen_port: 51820
  server_private_key: ""
  subnet: "10.0.8.0/24"
  gateway_ip: "10.0.8.1"

storage:
  path: ./data/uploads
  max_file_size_mb: 20
EOF
    echo '✅ config.yaml 已生成'
fi

# 更新 livekit.yaml 中的密钥
echo '📝 更新 LiveKit 配置...'
source .env
sed -i "s/api_key: .*/api_key: $LIVEKIT_API_KEY/" livekit.yaml
sed -i "s/api_secret: .*/api_secret: $LIVEKIT_API_SECRET/" livekit.yaml

# 创建数据目录
mkdir -p data/uploads
mkdir -p web-admin

echo ''
echo '📋 配置信息:'
echo '========================================'
echo "服务器地址: http://$(grep server_ip config.yaml | cut -d'"' -f2):8080"
echo "Web 管理后台: http://$(grep server_ip config.yaml | cut -d'"' -f2):3000"
echo '========================================'
echo ''

# 拉取并启动服务
echo '📦 拉取镜像并启动服务...'
docker-compose pull
docker-compose up -d

echo ''
echo '✅ 部署完成!'
echo ''
echo '📖 后续步骤:'
echo '   1. 打开客户端，配置服务器地址'
echo '   2. 注册管理员账号（如需超管权限，在注册时填写 admin_token）'
echo '   3. 创建房间，邀请好友加入'
echo ''
echo '🔧 常用命令:'
echo '   查看日志: docker-compose logs -f server'
echo '   重启服务: docker-compose restart'
echo '   停止服务: docker-compose down'
echo '   更新服务: docker-compose pull && docker-compose up -d'
echo ''
echo '⚠️  安全提示:'
echo '   - 请修改默认的 LiveKit API 密钥'
echo '   - 生产环境建议配置 HTTPS'
echo '   - 防火墙仅开放必要端口: 8080, 1935, 7880, 50000-50050/udp, 51820/udp'
