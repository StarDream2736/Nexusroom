#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer as root"
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ffmpeg
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache ffmpeg
  else
    echo "FFmpeg is required for WebRTC audio. Install it and run this installer again."
    exit 1
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="$(cd "$DEPLOYMENT_DIR/.." && pwd)"
TEMPLATE="$DEPLOYMENT_DIR/templates/server.yaml.template"

"$SCRIPT_DIR/build-direct.sh"
id nexusroom >/dev/null 2>&1 || useradd --system --home /var/lib/nexusroom --shell /usr/sbin/nologin nexusroom
install -d -m 0750 -o nexusroom -g nexusroom /var/lib/nexusroom/uploads /etc/nexusroom
install -m 0755 "$DEPLOYMENT_DIR/data/bin/nexusroom" /usr/local/bin/nexusroom

if [[ ! -f /etc/nexusroom/config.yaml ]]; then
	MEDIA_PUBLIC_IP="${NEXUSROOM_PUBLIC_IP:-}"
  PUBLIC_IP="${NEXUSROOM_PUBLIC_IP:-$(curl -fsS --max-time 5 https://api.ipify.org || true)}"
  [[ -n "$PUBLIC_IP" ]] || { echo "Set NEXUSROOM_PUBLIC_IP"; exit 1; }
  cp "$TEMPLATE" /etc/nexusroom/config.yaml
  sed -i \
    -e "s|YOUR_IP|$PUBLIC_IP|g" \
    -e "s|DATA_DIR|/var/lib/nexusroom|g" \
    -e "s|CHANGE_ME_JWT|$(openssl rand -hex 32)|g" \
    -e "s|CHANGE_ME_ADMIN|$(openssl rand -hex 24)|g" \
    -e "s|CHANGE_ME_TURN_USER|nexusroom-$(openssl rand -hex 4)|g" \
    -e "s|CHANGE_ME_TURN_PASSWORD|$(openssl rand -hex 24)|g" \
    /etc/nexusroom/config.yaml
  if [[ -n "$MEDIA_PUBLIC_IP" ]]; then
    sed -i -e "s|  public_ip: \"\"|  public_ip: \"$MEDIA_PUBLIC_IP\"|" /etc/nexusroom/config.yaml
  fi
  chmod 0640 /etc/nexusroom/config.yaml
  chown root:nexusroom /etc/nexusroom/config.yaml
fi

install -m 0644 "$DEPLOYMENT_DIR/systemd/nexusroom.service" /etc/systemd/system/nexusroom.service
systemctl daemon-reload
systemctl enable --now nexusroom
echo "NexusRoom direct deployment is running"
