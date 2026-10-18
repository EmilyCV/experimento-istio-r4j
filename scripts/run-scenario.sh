#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SCENARIO="${1:?Usage: run-scenario.sh <SCENARIO> <VARIANT> [REPS]}"
VARIANT="${2:?Usage: run-scenario.sh <SCENARIO> <VARIANT> [REPS]}"
REPS="${3:-5}"

NAMESPACE="exp-${VARIANT}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="$ROOT_DIR/results/${TIMESTAMP}/${SCENARIO}/${VARIANT}"

source "$ROOT_DIR/versions.env"

RPS="${RPS:-50}"
DURATION="${DURATION:-3m}"
WARMUP="${WARMUP:-1m}"

echo "=== Scenario: $SCENARIO | Variant: $VARIANT | Reps: $REPS ==="
echo "  Namespace: $NAMESPACE"
echo "  RPS: $RPS | Duration: $DURATION | Warmup: $WARMUP"
echo "  Results: $RESULT_DIR"
echo ""

SERVICE_A_POD=$(kubectl -n "$NAMESPACE" get pod -l app=service-a -o jsonpath='{.items[0].metadata.name}')
SERVICE_C_PODS=$(kubectl -n "$NAMESPACE" get pod -l app=service-c -o jsonpath='{.items[*].metadata.name}')

get_service_a_url() {
  kubectl -n "$NAMESPACE" port-forward svc/service-a 18080:8080 &
  PF_PID=$!
  sleep 2
  echo "http://localhost:18080"
}

inject_fault() {
  local fault_json="$1"
  echo "  Injecting fault: $fault_json"
  for pod in $SERVICE_C_PODS; do
    kubectl -n "$NAMESPACE" exec "$pod" -c app -- \
      curl -s -X POST -H "Content-Type: application/json" \
      -d "$fault_json" http://localhost:8080/admin/fault || true
  done
}

reset_fault() {
  echo "  Resetting fault"
  for pod in $SERVICE_C_PODS; do
    kubectl -n "$NAMESPACE" exec "$pod" -c app -- \
      curl -s -X POST -H "Content-Type: application/json" \
      -d '{"reset":true}' http://localhost:8080/admin/fault || true
  done
}

cleanup() {
  if [ -n "${PF_PID:-}" ]; then
    kill "$PF_PID" 2>/dev/null || true
  fi
  reset_fault
}
trap cleanup EXIT

BASE_URL=$(get_service_a_url)

for rep in $(seq 1 "$REPS"); do
  REP_DIR="${RESULT_DIR}/rep${rep}"
  mkdir -p "$REP_DIR"

  echo ""
  echo "--- Rep $rep/$REPS ---"

  reset_fault
  sleep 2

  EVENT_FILE="${REP_DIR}/events.jsonl"
  echo "{\"event\":\"start\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"scenario\":\"$SCENARIO\",\"variant\":\"$VARIANT\",\"rep\":$rep}" > "$EVENT_FILE"

  case "$SCENARIO" in
    S0|S1)
      # No fault injection
      ;;
    S2)
      inject_fault '{"delayMs":800,"delayPercent":50}'
      echo "{\"event\":\"fault_injected\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"delay\",\"delayMs\":800,\"delayPercent\":50}" >> "$EVENT_FILE"
      ;;
    S3)
      inject_fault '{"errorPercent":30,"errorStatus":503}'
      echo "{\"event\":\"fault_injected\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"error\",\"errorPercent\":30,\"errorStatus\":503}" >> "$EVENT_FILE"
      ;;
    S4)
      inject_fault '{"errorPercent":100,"errorStatus":503}'
      echo "{\"event\":\"fault_injected\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"error\",\"errorPercent\":100,\"errorStatus\":503}" >> "$EVENT_FILE"
      ;;
    S5)
      # Fault for 60s, then reset
      inject_fault '{"errorPercent":100,"errorStatus":503}'
      echo "{\"event\":\"fault_injected\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"error\",\"errorPercent\":100}" >> "$EVENT_FILE"
      (
        sleep 60
        reset_fault
        echo "{\"event\":\"fault_reset\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$EVENT_FILE"
      ) &
      FAULT_RESET_PID=$!
      ;;
    S6)
      inject_fault '{"errorPercent":30,"errorStatus":503}'
      echo "{\"event\":\"fault_injected\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"error\",\"errorPercent\":30}" >> "$EVENT_FILE"
      ;;
    *)
      echo "Unknown scenario: $SCENARIO"
      exit 1
      ;;
  esac

  echo "  Running k6..."
  k6 run \
    -e "BASE_URL=${BASE_URL}" \
    -e "RPS=${RPS}" \
    -e "DURATION=${DURATION}" \
    -e "WARMUP=${WARMUP}" \
    -e "OUTPUT_PATH=${REP_DIR}/results.json" \
    --out "csv=${REP_DIR}/results.csv" \
    "$ROOT_DIR/load/test.js" 2>&1 | tee "${REP_DIR}/k6.log"

  if [ -n "${FAULT_RESET_PID:-}" ]; then
    wait "$FAULT_RESET_PID" 2>/dev/null || true
    unset FAULT_RESET_PID
  fi

  echo "{\"event\":\"end\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$EVENT_FILE"

  reset_fault
  sleep 5
done

echo ""
echo "=== All $REPS reps complete for $SCENARIO/$VARIANT ==="
echo "  Results in: $RESULT_DIR"
