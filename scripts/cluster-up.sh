#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/versions.env"

CLUSTER_NAME="${CLUSTER_NAME:-exp-cluster}"

echo "=== Creating kind cluster: $CLUSTER_NAME ==="

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '$CLUSTER_NAME' already exists. Delete it first with: kind delete cluster --name $CLUSTER_NAME"
  exit 0
fi

kind create cluster \
  --name "$CLUSTER_NAME" \
  --config "$ROOT_DIR/k8s/kind-config.yaml" \
  --wait 120s

echo "=== Cluster ready ==="
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes -o wide

echo ""
echo "=== Creating experiment namespaces ==="
for ns in exp-baseline exp-istio exp-r4j exp-istio-nopolicy exp-both; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# Label the istio namespaces for sidecar injection
kubectl label namespace exp-istio istio-injection=enabled --overwrite
kubectl label namespace exp-istio-nopolicy istio-injection=enabled --overwrite
kubectl label namespace exp-both istio-injection=enabled --overwrite

echo ""
echo "=== Namespaces ==="
kubectl get namespaces | grep exp-

echo ""
echo "Done. Next: run scripts/istio-install.sh"
