# Retry e Circuit Breaker no Istio vs Resilience4j

Ambiente experimental reprodutível para a monografia **"Retry e Circuit Breaker no Istio: Uma Análise da Contenção de Falhas em Cascata em Microsserviços Cloud-Native"**.

## Objetivo

Comparar duas abordagens de implementação dos padrões **retry (com timeout)** e **circuit breaker** em uma cadeia de microsserviços:

- **Variante ISTIO:** resiliência no service mesh (Istio/Envoy sidecar), código sem lógica de resiliência.
- **Variante R4J:** resiliência no código (Resilience4j + Spring Boot), sem sidecar.
- **Baseline:** sem resiliência e sem sidecar (controle).
- **ISTIO-nopolicy:** com sidecar, mas sem políticas de retry/CB (isola o custo do proxy).

## Topologia

```
k6 ──▶ service-a (borda) ──▶ service-b (intermediário) ──▶ service-c (falha controlada)
       GET /api/order/{id}    GET /api/stock/{id}          GET /api/price/{id}
```

Os três serviços compartilham o mesmo código-base. A diferença entre variantes é apenas onde a resiliência está configurada.

## Equivalência de parâmetros

Os parâmetros de resiliência estão centralizados em [`params.yaml`](params.yaml). A tabela abaixo mostra a correspondência:

| Parâmetro | Istio | Resilience4j | Valor |
|---|---|---|---|
| Timeout por tentativa | `retries.perTryTimeout` | `TimeLimiter.timeoutDuration` | 500 ms |
| Timeout total | `timeout` (VirtualService) | Timeout do cliente HTTP | 2 s |
| Tentativas totais | `retries.attempts` = **2** (+ 1ª) | `Retry.maxAttempts` = **3** (inclui 1ª) | 3 |
| Condições de retry | `retryOn: 5xx,reset,...` | `retryExceptions` equivalentes | — |
| Backoff | Envoy: 25 ms base + jitter | R4J: `waitDuration` = 25 ms | 25 ms |
| CB: limite de falhas | `consecutive5xxErrors: 5` | `failureRateThreshold: 50%` (janela 10) | — |
| CB: tempo aberto | `baseEjectionTime: 30s` | `waitDurationInOpenState: 30s` | 30 s |

### Diferença semântica dos circuit breakers (importante)

O circuit breaker do **Istio** (outlier detection) opera por **ejeção de instâncias**: remove endpoints com falhas consecutivas do pool de balanceamento. O service-c roda com **2 réplicas** para que esse mecanismo funcione.

O circuit breaker do **Resilience4j** opera por **abertura de circuito**: bloqueia todas as chamadas para a dependência quando a taxa de falhas atinge o threshold, dentro do processo que faz a chamada.

Os dois **não são semanticamente idênticos**. Os parâmetros foram aproximados da seguinte forma:
- `consecutive5xxErrors: 5` no Istio ≈ `minimumNumberOfCalls: 5` + `failureRateThreshold: 50%` no R4J
- `baseEjectionTime: 30s` ≈ `waitDurationInOpenState: 30s`
- `maxEjectionPercent: 100` permite que o Istio ejete todas as instâncias, aproximando o efeito do circuito aberto do R4J

### Nota sobre `perTryTimeout`

O `perTryTimeout` do Istio é o **timeout de cada tentativa individual**, não o intervalo entre tentativas. O `timeout` no `VirtualService` é o timeout total da rota (abrange todas as tentativas).

## Versões

Todas as versões estão fixadas em [`versions.env`](versions.env).

## Pré-requisitos

- Docker Desktop (12 GB RAM, 4+ cores alocados)
- [kind](https://kind.sigs.k8s.io/) v0.25+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.31+
- [istioctl](https://istio.io/latest/docs/setup/getting-started/#download) v1.24+
- [Helm](https://helm.sh/docs/intro/install/) v3.x
- [k6](https://k6.io/docs/getting-started/installation/) v0.54+
- Java 21 (JDK)
- Python 3.12+ (para análise)

## Uso rápido

```bash
# 1. Infraestrutura
make cluster-up
make istio-install
make observability-install

# 2. Build e deploy
make build-images
make deploy-all

# 3. Verificar pods
make status

# 4. Calibrar carga
make calibrate

# 5. Rodar um cenário
make run SCENARIO=S1 VARIANT=istio REPS=1

# 6. Rodar todos os cenários
make run-all

# 7. Análise
make analyze

# 8. Cleanup
make cluster-down
```

## Cenários

| ID | Nome | Falha no service-c | Objetivo |
|---|---|---|---|
| S0 | Aquecimento | nenhuma | aquecer JVM (dados descartados) |
| S1 | Performance normal | nenhuma | latência e throughput sem falhas |
| S2 | Latência | +800 ms em 50% | timeout e retry |
| S3 | Erros transitórios | 503 em 30% | efetividade do retry |
| S4 | Erros persistentes | 503 em 100% por 60 s | abertura do CB e contenção |
| S5 | Recuperação | S4 + reset | tempo de recuperação |
| S6 | Retry duplicado | 503 em 30% (Istio+R4J) | multiplicação de tentativas |

## Injeção de falhas

A falha é injetada via endpoint administrativo do service-c (`POST /admin/fault`), igual nas duas variantes, garantindo comparação justa. O Istio fault injection é usado apenas como experimento complementar, nunca na comparação principal.

## Namespaces

| Namespace | Sidecar | Resiliência | Uso |
|---|---|---|---|
| `exp-baseline` | Não | Nenhuma | Controle |
| `exp-istio` | Sim | Istio (VS + DR) | Variante Istio |
| `exp-r4j` | Não | Resilience4j | Variante R4J |
| `exp-istio-nopolicy` | Sim | Nenhuma | Custo do sidecar |
| `exp-both` | Sim | Istio + R4J | Cenário S6 |

## Recursos

Os pods de aplicação usam os mesmos `requests` e `limits` em todas as variantes (ver `params.yaml`). O consumo do sidecar Envoy é reportado separadamente nos resultados.

## Limitações

- **Ambiente local:** os resultados refletem um notebook com recursos limitados, não um cluster de produção.
- **Versão única do Istio:** testado apenas com Istio 1.24.x.
- **Aplicação sintética:** os serviços simulam carga de CPU mínima. Aplicações reais teriam comportamento diferente.
- **Parâmetros:** os valores de retry, timeout e CB foram escolhidos para o experimento. Não devem ser generalizados para produção.
- **Circuit breakers não são idênticos:** outlier detection (Istio) e circuit breaker (R4J) têm semânticas diferentes (ver seção acima).
- **Sem fallback de negócio:** as comparações principais não usam fallback, para não mascarar falhas.

## Estrutura

```
├── README.md
├── HYPOTHESES.md          # Hipóteses definidas antes do experimento
├── versions.env           # Versões fixadas
├── params.yaml            # Parâmetros de resiliência
├── Makefile
├── services/              # Código Java (Spring Boot)
├── k8s/
│   ├── kind-config.yaml
│   ├── base/              # Deployments/Services comuns
│   ├── istio/             # VirtualService, DestinationRule
│   ├── r4j/
│   ├── baseline/
│   ├── istio-nopolicy/
│   └── both/              # Cenário S6
├── load/                  # Scripts k6
├── scripts/               # Automação
├── analysis/              # Scripts Python
└── results/               # Dados (ignorado no git)
```
