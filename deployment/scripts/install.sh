#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$DEPLOYMENT_DIR/config/server.yaml"
TEMPLATE="$DEPLOYMENT_DIR/templates/server.yaml.template"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required: https://docs.docker.com/engine/install/"
  exit 1
fi
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "Docker Compose is required"
  exit 1
fi

mkdir -p "$DEPLOYMENT_DIR/config" "$DEPLOYMENT_DIR/data/uploads"
if [[ ! -f "$CONFIG" ]]; then
  PUBLIC_IP="${NEXUSROOM_PUBLIC_IP:-$(curl -fsS --max-time 5 https://api.ipify.org || true)}"
  if [[ -z "$PUBLIC_IP" ]]; then
    echo "Set NEXUSROOM_PUBLIC_IP before installation"
    exit 1
  fi
  JWT_SECRET="$(openssl rand -hex 32)"
  ADMIN_TOKEN="$(openssl rand -hex 24)"
  TURN_USER="nexusroom-$(openssl rand -hex 4)"
  TURN_PASSWORD="$(openssl rand -hex 24)"
  cp "$TEMPLATE" "$CONFIG"
  sed -i \
    -e "s|YOUR_IP|$PUBLIC_IP|g" \
    -e "s|DATA_DIR|/app/data|g" \
    -e "s|CHANGE_ME_JWT|$JWT_SECRET|g" \
    -e "s|CHANGE_ME_ADMIN|$ADMIN_TOKEN|g" \
    -e "s|CHANGE_ME_TURN_USER|$TURN_USER|g" \
    -e "s|CHANGE_ME_TURN_PASSWORD|$TURN_PASSWORD|g" \
    "$CONFIG"
  chmod 600 "$CONFIG"
  echo "Generated $CONFIG"
  echo "Initial admin token: $ADMIN_TOKEN"
fi

cd "$DEPLOYMENT_DIR"
"${COMPOSE[@]}" up -d --build
echo "NexusRoom is running as one container"
echo "HTTP: http://$(grep 'public_ip:' "$CONFIG" | awk '{gsub(/\"/,"",$2); print $2}'):8080"
echo "RTMP: rtmp://$(grep 'public_ip:' "$CONFIG" | awk '{gsub(/\"/,"",$2); print $2}'):1935/live"
