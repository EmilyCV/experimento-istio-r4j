#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPS="${REPS:-5}"
SCENARIOS="S0 S1 S2 S3 S4 S5"
VARIANTS="baseline istio r4j istio-nopolicy"

echo "=== Running all scenarios ==="
echo "  Scenarios: $SCENARIOS"
echo "  Variants: $VARIANTS"
echo "  Reps: $REPS"
echo ""

# S0 (warmup) — run once per variant, discard results
for variant in $VARIANTS; do
  echo ">>> Warmup: S0 / $variant"
  bash "$SCRIPT_DIR/run-scenario.sh" S0 "$variant" 1
done

# S1-S5 — full experiment
for scenario in S1 S2 S3 S4 S5; do
  for variant in $VARIANTS; do
    echo ""
    echo ">>> $scenario / $variant"
    bash "$SCRIPT_DIR/run-scenario.sh" "$scenario" "$variant" "$REPS"
  done
done

# S6 — retry duplication (only in exp-both namespace)
echo ""
echo ">>> S6 / both"
bash "$SCRIPT_DIR/run-scenario.sh" S6 both "$REPS"

echo ""
echo "=== All runs complete ==="
