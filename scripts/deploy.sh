#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANT="${1:?Usage: deploy.sh <variant> (baseline|istio|r4j|istio-nopolicy|both)}"
NAMESPACE="exp-${VARIANT}"

echo "=== Deploying variant: $VARIANT → namespace: $NAMESPACE ==="

if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "Namespace $NAMESPACE does not exist. Run 'make cluster-up' first."
  exit 1
fi

kubectl apply -k "$ROOT_DIR/k8s/${VARIANT}"

echo ""
echo "=== Waiting for pods to be ready ==="
kubectl -n "$NAMESPACE" rollout status deployment/service-a --timeout=120s
kubectl -n "$NAMESPACE" rollout status deployment/service-b --timeout=120s
kubectl -n "$NAMESPACE" rollout status deployment/service-c --timeout=120s

echo ""
echo "=== Pods in $NAMESPACE ==="
kubectl -n "$NAMESPACE" get pods -o wide

echo ""
echo "Done."
