#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NAMESPACE="exp-baseline"

echo "=== Calibration: finding baseline capacity ==="
echo "  Running increasing RPS against $NAMESPACE until p95 degrades"
echo ""

kubectl -n "$NAMESPACE" port-forward svc/service-a 18080:8080 &
PF_PID=$!
sleep 2
trap "kill $PF_PID 2>/dev/null || true" EXIT

BASE_URL="http://localhost:18080"

for rps in 10 20 30 50 75 100 150; do
  echo "--- Testing RPS=$rps ---"
  k6 run \
    -e "BASE_URL=${BASE_URL}" \
    -e "RPS=${rps}" \
    -e "DURATION=30s" \
    -e "WARMUP=10s" \
    -e "OUTPUT_PATH=/dev/null" \
    "$ROOT_DIR/load/test.js" 2>&1 | grep -E '(http_req_duration|success_rate|http_reqs)' || true
  echo ""
  sleep 5
done

echo ""
echo "=== Calibration complete ==="
echo "Choose ~60-70% of the max RPS where p95 < 100ms and success_rate = 100%."
echo "Set RPS in params.yaml and export RPS=<value> before running experiments."
