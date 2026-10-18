# Makefile — Experimento Istio vs Resilience4j
# Uso: make <target>
# Exemplos:
#   make cluster-up istio-install observability-install
#   make build-images deploy-all
#   make run SCENARIO=S1 VARIANT=istio REPS=1
#   make run-all
#   make analyze
#   make cluster-down

SHELL := /bin/bash
.DEFAULT_GOAL := help

CLUSTER_NAME ?= exp-cluster
SCENARIO     ?= S1
VARIANT      ?= baseline
REPS         ?= 5
IMAGE_TAG    ?= latest
REGISTRY     ?= localhost

export CLUSTER_NAME

# ─── Stage 1: Infrastructure ─────────────────────────────────────────

.PHONY: cluster-up
cluster-up: ## Create kind cluster and namespaces
	@bash scripts/cluster-up.sh

.PHONY: istio-install
istio-install: ## Install Istio (sidecar mode)
	@bash scripts/istio-install.sh

.PHONY: observability-install
observability-install: ## Install Prometheus + Grafana
	@bash scripts/observability-install.sh

.PHONY: infra
infra: cluster-up istio-install observability-install ## Full infrastructure setup

# ─── Stage 2: Build & Deploy ─────────────────────────────────────────

.PHONY: build-images
build-images: ## Build Docker images for all services
	@bash scripts/build-images.sh

.PHONY: load-images
load-images: ## Load images into kind cluster
	@bash scripts/load-images.sh

.PHONY: deploy-baseline
deploy-baseline: ## Deploy services in exp-baseline namespace
	@bash scripts/deploy.sh baseline

.PHONY: deploy-istio
deploy-istio: ## Deploy services in exp-istio namespace (with policies)
	@bash scripts/deploy.sh istio

.PHONY: deploy-r4j
deploy-r4j: ## Deploy services in exp-r4j namespace
	@bash scripts/deploy.sh r4j

.PHONY: deploy-istio-nopolicy
deploy-istio-nopolicy: ## Deploy services in exp-istio-nopolicy namespace
	@bash scripts/deploy.sh istio-nopolicy

.PHONY: deploy-both
deploy-both: ## Deploy services in exp-both namespace (S6)
	@bash scripts/deploy.sh both

.PHONY: deploy-all
deploy-all: deploy-baseline deploy-istio deploy-r4j deploy-istio-nopolicy deploy-both ## Deploy all variants

# ─── Stage 3: Calibration & Tests ────────────────────────────────────

.PHONY: calibrate
calibrate: ## Find baseline capacity (run before experiments)
	@bash scripts/calibrate.sh

.PHONY: run
run: ## Run a scenario: make run SCENARIO=S3 VARIANT=istio REPS=5
	@bash scripts/run-scenario.sh $(SCENARIO) $(VARIANT) $(REPS)

.PHONY: run-all
run-all: ## Run all scenarios × all variants × 5 reps
	@bash scripts/run-all.sh

# ─── Stage 4: Analysis ───────────────────────────────────────────────

.PHONY: analyze
analyze: ## Run analysis script (Python)
	@cd analysis && python analyze.py

# ─── Cleanup ─────────────────────────────────────────────────────────

.PHONY: cluster-down
cluster-down: ## Delete kind cluster
	@bash scripts/cluster-down.sh

.PHONY: clean-results
clean-results: ## Remove all result files
	@rm -rf results/*/

# ─── Status & Debug ──────────────────────────────────────────────────

.PHONY: status
status: ## Show pods in all experiment namespaces
	@for ns in exp-baseline exp-istio exp-r4j exp-istio-nopolicy exp-both; do \
		echo "=== $$ns ==="; \
		kubectl -n $$ns get pods -o wide 2>/dev/null || echo "  (not deployed)"; \
		echo ""; \
	done

.PHONY: logs
logs: ## Show logs: make logs NS=exp-istio SVC=service-a
	kubectl -n $(NS) logs -l app=$(SVC) --tail=100 -f

# ─── Help ─────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'
