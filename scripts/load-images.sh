#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-exp-cluster}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=== Loading image into kind cluster ==="
kind load docker-image "experiment/service:${IMAGE_TAG}" --name "$CLUSTER_NAME"
echo "Done."
