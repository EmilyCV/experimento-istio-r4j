#!/usr/bin/env bash
set -euo pipefail

# Install experiment dependencies on Windows (Git Bash / MSYS2)
# Run from Git Bash as administrator for best results

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/versions.env"

echo "=== Checking and installing tools ==="
echo ""

# --- kind ---
if command -v kind &>/dev/null; then
  echo "[OK] kind $(kind version)"
else
  echo "[INSTALL] kind $KIND_VERSION"
  echo "  Option A (recommended): choco install kind"
  echo "  Option B: Download from https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-windows-amd64"
  echo "            and add to PATH"
fi
echo ""

# --- Helm ---
if command -v helm &>/dev/null; then
  echo "[OK] helm $(helm version --short)"
else
  echo "[INSTALL] helm"
  echo "  Option A (recommended): choco install kubernetes-helm"
  echo "  Option B: winget install Helm.Helm"
  echo "  Option C: https://helm.sh/docs/intro/install/"
fi
echo ""

# --- istioctl ---
if command -v istioctl &>/dev/null; then
  echo "[OK] istioctl $(istioctl version --short 2>/dev/null || echo 'unknown')"
else
  echo "[INSTALL] istioctl $ISTIO_VERSION"
  echo "  Download from: https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-win.zip"
  echo "  Extract and add to PATH"
  echo "  Or: choco install istioctl --version=${ISTIO_VERSION}"
fi
echo ""

# --- k6 ---
if command -v k6 &>/dev/null; then
  echo "[OK] k6 $(k6 version)"
else
  echo "[INSTALL] k6 $K6_VERSION"
  echo "  Option A (recommended): choco install k6"
  echo "  Option B: winget install k6.k6"
  echo "  Option C: https://github.com/grafana/k6/releases"
fi
echo ""

# --- Docker ---
if docker info &>/dev/null 2>&1; then
  echo "[OK] Docker $(docker version --format '{{.Server.Version}}')"
else
  echo "[WARNING] Docker Desktop is not running. Start it before proceeding."
fi
echo ""

echo "=== After installing, run this script again to verify ==="
