#!/usr/bin/env bash
# Source this file to add tool paths to the shell
# Usage: source scripts/env.sh

# kind (WinGet)
KIND_DIR="$(ls -d "$LOCALAPPDATA/Microsoft/WinGet/Packages/Kubernetes.kind"* 2>/dev/null | head -1)"
if [ -n "$KIND_DIR" ]; then
  export PATH="$KIND_DIR:$PATH"
fi

# helm (WinGet)
HELM_DIR="$(ls -d "$LOCALAPPDATA/Microsoft/WinGet/Packages/Helm.Helm"*/windows-amd64 2>/dev/null | head -1)"
if [ -n "$HELM_DIR" ]; then
  export PATH="$HELM_DIR:$PATH"
fi

# k6
if [ -d "/c/Program Files/k6" ]; then
  export PATH="/c/Program Files/k6:$PATH"
fi

# istioctl
if [ -d "/c/tools/istio" ]; then
  export PATH="/c/tools/istio:$PATH"
fi
ISTIO_DIR="$(ls -d "$HOME/istio"*/bin 2>/dev/null | head -1)"
if [ -n "$ISTIO_DIR" ]; then
  export PATH="$ISTIO_DIR:$PATH"
fi

echo "PATH updated. Checking tools:"
kind version 2>/dev/null && echo "  kind: OK" || echo "  kind: NOT FOUND"
helm version --short 2>/dev/null && echo "  helm: OK" || echo "  helm: NOT FOUND"
istioctl version --remote=false 2>/dev/null && echo "  istioctl: OK" || echo "  istioctl: NOT FOUND"
k6 version 2>/dev/null && echo "  k6: OK" || echo "  k6: NOT FOUND"
