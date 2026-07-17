#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/deployment/data/bin"

command -v go >/dev/null 2>&1 || { echo "Go 1.25 or newer is required"; exit 1; }
command -v gcc >/dev/null 2>&1 || { echo "A C compiler is required for embedded SQLite"; exit 1; }
mkdir -p "$OUTPUT_DIR"
cd "$ROOT_DIR/server"
CGO_ENABLED=1 \
CGO_CFLAGS="-D_LARGEFILE64_SOURCE -D_GNU_SOURCE" \
go build -trimpath -ldflags="-s -w" -o "$OUTPUT_DIR/nexusroom" ./cmd/server
echo "Built $OUTPUT_DIR/nexusroom"
