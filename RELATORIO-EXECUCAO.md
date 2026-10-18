# Relatório de Execução — Experimento Istio vs R4J

**Data:** 2026-10-01
**Autor:** Claude (assistente) + Emily (orientação)

---

## 1. Visão Geral do Projeto

Monografia: *"Retry e Circuit Breaker no Istio: Uma Análise da Contenção de Falhas em Cascata em Microsserviços Cloud-Native"*

**Objetivo:** Comparar duas abordagens de resiliência (retry + circuit breaker):
- **ISTIO:** Resiliência no service mesh (Envoy sidecar)
- **R4J:** Resiliência na aplicação (Resilience4j + Spring Boot)
- **Baseline:** Sem resiliência (controle)
- **ISTIO-nopolicy:** Sidecar presente, sem políticas (isola custo do proxy)
- **Both (S6):** Istio + R4J simultâneo (demonstra retry storm)

**Topologia:** `k6 → service-a → service-b → service-c`

---

## 2. O que foi feito — Estrutura do Projeto (Etapas 1-3)

### 2.1 Aplicação Java (Clean Architecture)

**Diretório:** `services/`

Criada aplicação Spring Boot 3.4.1 com Java 21, estruturada em Clean Architecture:

- **Domain layer** (sem dependências de framework):
  - `domain/model/OrderResponse.java` — record(orderId, status, stock)
  - `domain/model/StockResponse.java` — record(productId, quantity, price)
  - `domain/model/PriceResponse.java` — record(productId, price, computeTimeMs)
  - `domain/model/FaultConfig.java` — record com lógica de injeção de falha (delay e erro por porcentagem)
  - `domain/port/out/StockServicePort.java` — interface de saída
  - `domain/port/out/PriceServicePort.java` — interface de saída

- **Application layer**:
  - `GetOrderUseCase.java` — @Profile("service-a"), usa StockServicePort
  - `GetStockUseCase.java` — @Profile("service-b"), usa PriceServicePort
  - `GetPriceUseCase.java` — @Profile("service-c"), simula trabalho CPU (5ms busy-wait), gerencia FaultConfig

- **Infrastructure adapters (inbound — controllers)**:
  - `OrderController.java` — GET /api/order/{id} (service-a)
  - `StockController.java` — GET /api/stock/{id} (service-b)
  - `PriceController.java` — GET /api/price/{id} (service-c) + contador Micrometer
  - `FaultAdminController.java` — POST/GET /admin/fault (configura injeção de falha em service-c)
  - `GlobalExceptionHandler.java` — trata FaultInjectedException

- **Infrastructure adapters (outbound — clientes HTTP, profile-conditional)**:
  - `StockRestAdapter.java` — @Profile("!r4j") — chamada HTTP simples
  - `PriceRestAdapter.java` — @Profile("!r4j") — chamada HTTP simples
  - `R4jStockAdapter.java` — @Profile("r4j") — @Retry + @CircuitBreaker
  - `R4jPriceAdapter.java` — @Profile("r4j") — @Retry + @CircuitBreaker

- **Configuração HTTP**: `RestClientConfig.java` — Apache HttpClient 5 com connection pool (100 total, 50 por rota)

- **Spring profiles YAML**:
  - `application.yaml` — porta 8080, actuator, métricas Micrometer, timeouts padrão (connect 500ms, read 3000ms)
  - `application-service-a.yaml` — nome + URL do service-b
  - `application-service-b.yaml` — nome + URL do service-c
  - `application-service-c.yaml` — nome
  - `application-r4j.yaml` — read-timeout 500ms (per-try), circuit breaker (COUNT_BASED, window 10, threshold 50%, wait 30s), retry (3 tentativas, 25ms backoff)

- **Decisão de timeout HTTP**:
  - R4J: 500ms (cada chamada é um try individual)
  - Istio/Baseline: 3000ms (Envoy faz retries internamente, app precisa de timeout maior)

- **Dockerfile**: Multi-stage build (maven:3.9-eclipse-temurin-21-alpine → eclipse-temurin:21-jre-alpine), JVM flags: -XX:+UseG1GC -XX:MaxRAMPercentage=75.0

### 2.2 Manifests Kubernetes

**Diretório:** `k8s/`

- **Base** (`k8s/base/`):
  - service-a.yaml, service-b.yaml, service-c.yaml — Deployment + Service
  - service-c com 2 replicas (necessário para Istio outlier detection)
  - Resources: 100m-500m CPU, 256Mi-512Mi RAM
  - Labels: `app.kubernetes.io/part-of: experiment`

- **Overlays** (Kustomize):
  - `k8s/baseline/` — namespace exp-baseline, profiles "service-x,baseline"
  - `k8s/r4j/` — namespace exp-r4j, profiles "service-x,r4j"
  - `k8s/istio/` — namespace exp-istio, profiles "service-x,istio" + VirtualService + DestinationRule
  - `k8s/istio-nopolicy/` — namespace exp-istio-nopolicy, sem políticas
  - `k8s/both/` — namespace exp-both, profiles "service-x,r4j" + VirtualService + DestinationRule

- **Istio resources** (em `k8s/istio/` e `k8s/both/`):
  - VirtualService: timeout 2s, retries 2 tentativas, perTryTimeout 500ms, retryOn 5xx,reset,connect-failure,gateway-error
  - DestinationRule: outlierDetection (5 erros 5xx consecutivos, interval 10s, ejeção 30s, maxEjection 100%), connectionPool

- **kind-config.yaml**: 1 control-plane + 2 workers, NodePorts (30000, 30001, 30300 Grafana, 30900 Prometheus)

### 2.3 Scripts

**Diretório:** `scripts/`

| Script | Função |
|---|---|
| `env.sh` | Configura PATH das ferramentas (kind, helm, istioctl, k6) |
| `cluster-up.sh` | Cria cluster kind + namespaces + labels istio-injection |
| `cluster-down.sh` | Destrói o cluster kind |
| `istio-install.sh` | Instala Istio com profile minimal |
| `observability-install.sh` | Instala Prometheus + Grafana via Helm + PodMonitor + ServiceMonitor |
| `build-images.sh` | Build da imagem Docker |
| `load-images.sh` | Carrega imagem no kind |
| `deploy.sh` | Deploy de um variante específico |
| `calibrate.sh` | Calibração de RPS alvo |
| `run-scenario.sh` | Executa um cenário (injeção de falha + k6) |
| `run-all.sh` | Executa todos os cenários/variantes sequencialmente |
| `install-tools.sh` | Instruções de instalação das ferramentas |

### 2.4 Load Testing

- **`load/test.js`** — Script k6 com constant-arrival-rate executor (open-loop), métricas custom (success_rate, errors_by_code), warmup em setup(), exporta JSON via handleSummary

### 2.5 Análise Estatística

- **`analysis/analyze.py`** — Carrega JSONs do k6, consolida em DataFrame, roda Mann-Whitney U para H1-H4, calcula Cliff's delta, gera gráficos CDF e barras, CSV com mean/std/CI95

### 2.6 Outros Arquivos

- **`versions.env`** — Versões pinadas para reprodutibilidade
- **`params.yaml`** — Fonte central de parâmetros do experimento
- **`HYPOTHESES.md`** — H1 a H4 com testes estatísticos definidos
- **`Makefile`** — Targets para todas as etapas

---

## 3. O que foi feito — Instalações e Ajustes na Máquina (Etapa 4)

### 3.1 Instalação do istioctl

- **Problema:** `istioctl` não estava no PATH de nenhuma sessão (Bash, PowerShell), apesar de funcionar no terminal MINGW64 da Emily
- **Busca realizada:** Procurei em WinGet packages, Downloads, usr/local/bin, scoop, msys64, Git Bash, .bashrc/.bash_profile — não encontrado em nenhum lugar
- **Solução:** Baixei `istioctl-1.24.2-win-amd64.zip` do GitHub releases do Istio e extraí em `C:\tools\istio\`
- **Atualização:** `scripts/env.sh` atualizado para incluir `/c/tools/istio` no PATH

### 3.2 Problema de PATH das ferramentas

- **Problema:** kind, helm, istioctl e k6 não estavam no PATH das sessões Bash/PowerShell do Claude Code
- **Caminhos encontrados:**
  - kind: `C:\Users\Emily\AppData\Local\Microsoft\WinGet\Packages\Kubernetes.kind_Microsoft.Winget.Source_8wekyb3d8bbwe\kind.exe`
  - helm: `C:\Users\Emily\AppData\Local\Microsoft\WinGet\Packages\Helm.Helm_Microsoft.Winget.Source_8wekyb3d8bbwe\windows-amd64\helm.exe`
  - k6: `C:\Program Files\k6\k6.exe`
  - istioctl: `C:\tools\istio\istioctl.exe` (instalado manualmente)
- **Solução:** Cada comando executado usava `export PATH=` com os caminhos completos

### 3.3 Correção do nome da imagem Docker

- **Problema:** Os manifests K8s referenciavam `experiment/service:latest`, mas a imagem foi buildada como `resilience-service:latest`
- **Erro:** `ErrImagePull` — tentava baixar do Docker Hub
- **Correção:** Alterados os 3 arquivos base (`service-a.yaml`, `service-b.yaml`, `service-c.yaml`) para usar `resilience-service:latest`

### 3.4 Correção dos health probes

- **Problema:** `initialDelaySeconds: 30` no liveness probe era insuficiente — Spring Boot demorava ~36s para iniciar no kind com recursos limitados
- **Erro:** Pods reiniciavam em loop (exit code 137 — killed pelo kubelet)
- **Correção:** Substituí `initialDelaySeconds` por `startupProbe` nos 3 manifests base:
  ```yaml
  startupProbe:
    httpGet:
      path: /actuator/health/liveness
      port: 8080
    failureThreshold: 30
    periodSeconds: 5
  ```
  Isso permite até 150s de startup antes do liveness probe começar a atuar.

---

## 4. O que foi executado com sucesso no cluster

1. **Cluster kind criado** — 3 nodes (1 control-plane + 2 workers), K8s v1.37.0
2. **5 namespaces criados** — exp-baseline, exp-istio, exp-r4j, exp-istio-nopolicy, exp-both
3. **3 namespaces com istio-injection=enabled** — exp-istio, exp-istio-nopolicy, exp-both
4. **Istio 1.24.2 instalado** — istiod rodando em istio-system
5. **Prometheus + Grafana instalados** — kube-prometheus-stack via Helm, PodMonitor + ServiceMonitor criados
6. **Imagem Docker buildada** — `resilience-service:latest`, carregada nos 3 nodes do kind
7. **Baseline deployado e validado**:
   - Chain A→B→C funcionando: `GET /api/order/prod-001` retorna resposta completa
   - Fault injection funcionando: `POST /admin/fault` com `errorPercent: 50` produz mix de 200/503
   - Métricas Prometheus: `service_c_requests_total` contando corretamente
8. **Outros 4 variantes deployados** — mas não finalizaram o startup (cluster sobrecarregado com ~20 pods simultâneos)

---

## 5. Onde parou — Problema final

Tentei subir todos os 5 variantes simultaneamente (20 pods totais), o que sobrecarregou o cluster kind local (12GB RAM / 4-6 cores). Os pods estavam em rolling update e o kubectl começou a dar TLS timeout.

**Cluster kind ainda existe** mas pode estar instável. Precisa ser deletado com:
```bash
kind delete cluster --name exp-cluster
```
(Pode ser necessário reiniciar o Docker Desktop antes se estiver travado.)

---

## 6. Próximos Passos Planejados

### 6.1 Recriar o cluster (de forma controlada)
```bash
# 1. Criar cluster
make cluster-up

# 2. Instalar Istio
make istio-install

# 3. Instalar observabilidade
make observability-install

# 4. Buildar e carregar imagem
make build-images
```

### 6.2 Executar experimentos (um variante por vez)

O script `run-all.sh` executa sequencialmente. A estratégia correta é:

1. Deploy de UM variante
2. Rodar todos os cenários (S0-S6) com 5 repetições
3. Limpar o namespace
4. Próximo variante

```bash
# Opção 1: Executar tudo de uma vez (sequencial)
make run-all

# Opção 2: Executar variante por variante
scripts/deploy.sh baseline
scripts/run-scenario.sh S0 baseline 5
scripts/run-scenario.sh S1 baseline 5
# ... S2 a S6
# Limpar e repetir para r4j, istio, etc.
```

### 6.3 Calibração

Antes dos cenários reais, rodar calibração para encontrar o RPS adequado:
```bash
make calibrate
```

### 6.4 Análise

Após todos os cenários:
```bash
make analyze
```

Gera: gráficos CDF, barras comparativas, CSV com estatísticas, testes Mann-Whitney U, Cliff's delta.

---

## 7. Versões das Ferramentas

| Ferramenta | Versão |
|---|---|
| Java | 21 |
| Spring Boot | 3.4.1 |
| Resilience4j | 2.2.0 |
| kind | 0.33.0 |
| K8s (node image) | v1.33.0 |
| Istio | 1.24.2 |
| kubectl | 1.34.1 |
| k6 | 2.2.0 |
| Helm | 4.3.0 |
| Docker Desktop | já instalado |

---

## 8. Estrutura de Diretórios

```
experimento-istio-r4j/
├── services/                    # App Java (Spring Boot + Clean Architecture)
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/java/com/experiment/resilience/
│       ├── domain/model/        # Records, FaultConfig
│       ├── domain/port/out/     # Interfaces de saída
│       ├── application/usecase/ # Use cases por service role
│       └── infrastructure/
│           ├── adapter/in/web/  # Controllers REST
│           ├── adapter/out/     # Adapters HTTP (plain + R4J)
│           └── config/          # RestClientConfig
├── k8s/
│   ├── kind-config.yaml
│   ├── base/                    # Deployments + Services base
│   ├── baseline/                # Overlay Kustomize
│   ├── r4j/
│   ├── istio/                   # + VirtualService + DestinationRule
│   ├── istio-nopolicy/
│   └── both/                    # + VirtualService + DestinationRule
├── scripts/                     # Shell scripts para cada etapa
├── load/test.js                 # Script k6
├── analysis/analyze.py          # Análise estatística
├── results/                     # Resultados (gerados pela execução)
├── versions.env                 # Versões pinadas
├── params.yaml                  # Parâmetros centrais
├── HYPOTHESES.md                # Hipóteses e testes estatísticos
└── Makefile                     # Orquestração
```
