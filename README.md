# Retry e Circuit Breaker: Istio × Resilience4j

Experimento da monografia de MBA em Engenharia de Software. Ele compara **retry + circuit breaker** implementados no **Istio (modo sidecar)** e no **Resilience4j**, avaliando características de qualidade da **ISO/IEC 25010**:

- **eficiência de desempenho:** comportamento temporal (latência p50 e p95) e utilização de recursos (CPU e memória, com o sidecar separado da aplicação);
- **manutenibilidade:** modificabilidade, por um roteiro manual.

## Em resumo

- **Dois serviços Spring Boot, numa única imagem:** o `service-a` (`GET /api/a/{id}`) chama o `service-b` (`GET /api/b/{id}`), que gasta 5 ms de CPU.
- **Três variantes**, executadas uma de cada vez num cluster kind local:
  - `baseline`: sem resiliência e sem sidecar;
  - `r4j`: Resilience4j no service-a;
  - `istio`: VirtualService e DestinationRule, com sidecar nos dois serviços.
- **Carga:** constante de 20 req/s com o k6, dentro do cluster; 10 repetições de 90 s por variante.
- **Teste de hipótese:** Mann-Whitney U unilateral (Istio > Resilience4j), correção de Bonferroni e δ de Cliff.
- **Cenário sem falhas:** mede-se **o custo de ter a resiliência configurada**, e não a resiliência em ação.

## Documentos

| Documento | Conteúdo |
|---|---|
| [GUIA.md](GUIA.md) | **Comece por aqui.** Conceitos, organização do código, passo a passo do zero até os resultados, tempos, erros comuns e limpeza. |
| [HIPOTESES.md](HIPOTESES.md) | Hipóteses H1–H3, unidade de análise e teste estatístico. |
| [PARAMETROS.md](PARAMETROS.md) | Parâmetros correspondentes de retry e circuit breaker nas duas abordagens. |
| [ROTEIRO-MODIFICABILIDADE.md](ROTEIRO-MODIFICABILIDADE.md) | Roteiro manual para medir o esforço de mudar o retry em cada abordagem. |

## Uso rápido

Depois de preparar o cluster (passos 5.1 a 5.6 do [GUIA.md](GUIA.md)):

```bash
./rodar-variante.sh baseline
```
```bash
./rodar-variante.sh r4j
```
```bash
./rodar-variante.sh istio
```
```bash
python analise.py
```

O resultado fica em `results/RESULTADOS.md`.

## Estrutura

```
├── GUIA.md, HIPOTESES.md, PARAMETROS.md, ROTEIRO-MODIFICABILIDADE.md
├── rodar-variante.sh        # executa uma variante (sobe, aquece, mede, remove)
├── analise.py               # testes estatísticos, RESULTADOS.md e gráficos
├── requirements.txt         # pacotes Python do analise.py
├── services/                # projeto Java (Clean Architecture), pom.xml e Dockerfile
├── k8s/
│   ├── kind-config.yaml     # cluster de um nó (Kubernetes 1.31)
│   ├── baseline/  r4j/  istio/   # YAML completo de cada variante
│   ├── k6/                  # script do k6 (ConfigMap) e Job
│   └── metrics-server/      # metrics-server v0.8.1 (para o kubectl top)
└── results/                 # dados de cada execução e RESULTADOS.md
```

A versão anterior, maior (5 variantes e 7 cenários com falhas), está guardada no branch `experimento-completo`.
