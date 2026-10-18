#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=== Building service image ==="
cd "$ROOT_DIR/services"
docker build -t "experiment/service:${IMAGE_TAG}" .

echo ""
echo "=== Image built: experiment/service:${IMAGE_TAG} ==="
docker images experiment/service
