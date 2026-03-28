#!/bin/bash
# ============================================================
# NexusRoom Server 一键部署脚本
# ============================================================
# 自动完成：环境检查 → 生成 .env → 生成 config.yaml → 更新 livekit.yaml → 启动服务
# ============================================================
set -e

echo '🚀 NexusRoom Server 部署脚本'
echo ''

# ── 前置检查 ──────────────────────────────────────────────

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

# ── 生成 .env ──────────────────────────────────────────────

if [ ! -f .env ]; then
    echo '📝 首次运行，生成 .env ...'
    cat > .env << EOF
# 自动生成 — 请根据需要修改
DB_PASSWORD=$(openssl rand -hex 16)
LIVEKIT_API_KEY=devkey$(openssl rand -hex 4)
LIVEKIT_API_SECRET=$(openssl rand -hex 32)
EOF
    echo '✅ .env 已创建（含随机密码/密钥）'
fi

source .env

# ── 生成 config.yaml ──────────────────────────────────────

if [ ! -f config.yaml ]; then
    echo '📝 生成 config.yaml ...'

    JWT_SECRET=$(openssl rand -hex 32)

    echo '🌐 检测服务器公网 IP ...'
    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || echo "YOUR_IP")
    echo "   检测到: $SERVER_IP"

    cp config.yaml.template config.yaml

    # 替换【必改】占位符
    sed -i "s/password: \"CHANGE_ME\"/password: \"$DB_PASSWORD\"/" config.yaml
    sed -i "s/jwt_secret: \"CHANGE_ME\"/jwt_secret: \"$JWT_SECRET\"/" config.yaml
    sed -i "s|public_url: ws://YOUR_IP:7880|public_url: ws://$SERVER_IP:7880|" config.yaml
    sed -i "s/api_key: \"CHANGE_ME\"/api_key: \"$LIVEKIT_API_KEY\"/" config.yaml
    sed -i "s/api_secret: \"CHANGE_ME\"/api_secret: \"$LIVEKIT_API_SECRET\"/" config.yaml
    sed -i "s/server_ip: \"YOUR_IP\"/server_ip: \"$SERVER_IP\"/" config.yaml

    echo '✅ config.yaml 已生成'
fi

# ── 生成 livekit.yaml ────────────────────────────────────

if [ ! -f livekit.yaml ]; then
    echo '📝 生成 livekit.yaml ...'
    cp livekit.yaml.template livekit.yaml

    SERVER_IP=$(grep 'server_ip' config.yaml | head -1 | sed 's/.*"\(.*\)".*/\1/')

    sed -i "s/  CHANGE_ME_KEY: CHANGE_ME_SECRET/  $LIVEKIT_API_KEY: $LIVEKIT_API_SECRET/" livekit.yaml
    sed -i "s/node_ip: YOUR_IP/node_ip: $SERVER_IP/" livekit.yaml
    sed -i "s/domain: YOUR_IP/domain: $SERVER_IP/" livekit.yaml

    echo '✅ livekit.yaml 已生成'
fi

# ── 生成 srs.conf（如果不存在） ──────────────────────────

if [ ! -f srs.conf ]; then
    echo '⚠️  srs.conf 不存在，请确保已放置到 deploy/ 目录'
fi

# ── 创建数据目录 ──────────────────────────────────────────

mkdir -p data/uploads
mkdir -p web-admin

# ── 输出配置摘要 ──────────────────────────────────────────

SERVER_IP=$(grep 'server_ip' config.yaml | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo ''
echo '📋 配置摘要:'
echo '========================================'
echo "  API 服务:      http://$SERVER_IP:8080"
echo "  网页直播入口:  http://$SERVER_IP:8881"
echo "  LiveKit 语音:  ws://$SERVER_IP:7880"
echo "  RTMP 推流:     rtmp://$SERVER_IP:1935/live/"
echo "  RTMP 推流(别名): rtmp://$SERVER_IP:8883/live/"
echo "  Web 管理后台:  http://$SERVER_IP:3000"
echo '========================================'
echo ''

# ── 启动服务 ──────────────────────────────────────────────

echo '📦 拉取镜像并启动服务...'
docker-compose pull
docker-compose up -d

echo ''
echo '✅ 部署完成!'
echo ''
echo '📖 后续步骤:'
echo '   1. 打开客户端 → 设置服务器地址 http://'"$SERVER_IP"':8080'
echo '   2. 注册管理员账号'
echo '   3. 创建房间，邀请好友加入'
echo ''
echo '🔧 常用命令:'
echo '   查看日志:   docker-compose logs -f server'
echo '   重启服务:   docker-compose restart'
echo '   停止服务:   docker-compose down'
echo '   更新镜像:   docker-compose pull && docker-compose up -d'
echo ''
echo '⚠️  防火墙需开放端口:'
echo '   8080          API 服务'
echo '   8881          网页直播入口'
echo '   1935          SRS RTMP 推流'
echo '   8883          SRS RTMP 推流别名'
echo '   8000/udp      SRS WebRTC 媒体'
echo '   7880          LiveKit 信令'
echo '   7881          LiveKit TCP 穿透'
echo '   3478/udp      TURN 服务器'
echo '   50000-50050/udp  WebRTC 媒体'
echo '   51820/udp     WireGuard VPN'
