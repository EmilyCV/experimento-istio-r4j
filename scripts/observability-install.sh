#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/versions.env"

echo "=== Installing Prometheus + Grafana (kube-prometheus-stack) ==="

# Add helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Install kube-prometheus-stack
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version "$PROMETHEUS_STACK_VERSION" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30900 \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30300 \
  --set grafana.adminPassword=admin \
  --set alertmanager.enabled=false \
  --set prometheus.prometheusSpec.resources.requests.cpu=100m \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
  --set prometheus.prometheusSpec.retention=6h \
  --set grafana.resources.requests.cpu=50m \
  --set grafana.resources.requests.memory=128Mi \
  --wait --timeout 180s

echo ""
echo "=== Creating PodMonitor for experiment namespaces ==="
cat <<'PODMON' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: experiment-apps
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames:
      - exp-baseline
      - exp-istio
      - exp-r4j
      - exp-istio-nopolicy
      - exp-both
  selector:
    matchLabels:
      app.kubernetes.io/part-of: experiment
  podMetricsEndpoints:
    - port: http
      path: /actuator/prometheus
      interval: 5s
PODMON

echo ""
echo "=== Creating ServiceMonitor for Istio ==="
cat <<'SVCMON' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-mesh
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames:
      - istio-system
  selector:
    matchLabels:
      app: istiod
  endpoints:
    - port: http-monitoring
      interval: 10s
SVCMON

echo ""
echo "=== Monitoring stack ready ==="
echo "  Prometheus: http://localhost:30900"
echo "  Grafana:    http://localhost:30300  (admin/admin)"
kubectl -n monitoring get pods

echo ""
echo "Done. Next: build and deploy services."
