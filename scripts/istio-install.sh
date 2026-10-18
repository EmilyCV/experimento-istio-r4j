#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/versions.env"

echo "=== Installing Istio $ISTIO_VERSION ==="

# Check if istioctl is available
if ! command -v istioctl &>/dev/null; then
  echo "istioctl not found. Install it:"
  echo "  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -"
  echo "  export PATH=\$PWD/istio-$ISTIO_VERSION/bin:\$PATH"
  exit 1
fi

INSTALLED_VERSION=$(istioctl version --short 2>/dev/null | head -1 || echo "none")
echo "  istioctl version: $INSTALLED_VERSION"

# Install with minimal profile (lighter for local experiments)
# Sidecar mode (not ambient)
istioctl install --set profile=minimal \
  --set meshConfig.defaultConfig.holdApplicationUntilProxyStarts=true \
  --set meshConfig.accessLogFile=/dev/stdout \
  --set values.pilot.resources.requests.cpu=100m \
  --set values.pilot.resources.requests.memory=256Mi \
  --set values.global.proxy.resources.requests.cpu=50m \
  --set values.global.proxy.resources.requests.memory=64Mi \
  --set values.global.proxy.resources.limits.cpu=200m \
  --set values.global.proxy.resources.limits.memory=256Mi \
  -y

echo ""
echo "=== Waiting for Istio pods ==="
kubectl -n istio-system wait --for=condition=ready pod --all --timeout=120s

echo ""
echo "=== Istio installation ==="
kubectl -n istio-system get pods
istioctl version

echo ""
echo "=== Enabling Envoy stats for circuit breaker metrics ==="
# Enable stats for outlier detection and retry metrics
kubectl -n istio-system get configmap istio -o yaml | \
  sed 's/statsInclusionPrefixes: .*//' | \
  kubectl apply -f - 2>/dev/null || true

echo ""
echo "=== Verifying sidecar injection labels ==="
kubectl get namespace -L istio-injection | grep exp-

echo ""
echo "Done. Next: run scripts/observability-install.sh"
