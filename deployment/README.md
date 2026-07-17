# NexusRoom deployment

NexusRoom now runs as one server process. SQLite, WebSocket signaling, the voice SFU, RTMP ingest, HTTP-FLV/WebRTC playback, TURN, embedded web pages, and WireGuard coordination are all first-party modules in the same binary.

No PostgreSQL, Redis, nginx, LiveKit server, or SRS server is required.

## Docker deployment

```bash
cd deployment
chmod +x scripts/*.sh
./scripts/install.sh
```

The installer creates `config/server.yaml`, persists application state below `data/`, builds the local server source, and starts one `nexusroom` container.

## Direct Linux deployment

Install Go 1.25+, GCC, WireGuard tools, iproute2, and iptables first. Then run:

```bash
cd deployment
chmod +x scripts/*.sh
sudo ./scripts/install-direct.sh
```

The direct installer builds the same source, installs `/usr/local/bin/nexusroom`, writes `/etc/nexusroom/config.yaml`, stores state in `/var/lib/nexusroom`, and enables `nexusroom.service`.

## Network ports

| Port | Purpose |
| --- | --- |
| `8080/tcp` | API, WebSocket, embedded web player, HTTP-FLV |
| `1935/tcp` | RTMP ingest |
| `3478/udp` | STUN/TURN |
| `50000-50050/udp` | direct WebRTC media |
| `51000-51100/udp` | TURN relay allocation |
| `51820/udp` | WireGuard |

Keep `config/server.yaml` private because it contains JWT, administrator, and TURN credentials. Back up `data/nexusroom.db` and `data/uploads/`.
