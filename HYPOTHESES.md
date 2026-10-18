# Hipóteses do Experimento

Definidas **antes** da execução. O experimento verifica se os dados as sustentam ou não — não serve para comprová-las.

## H1 — Performance (overhead do proxy)

**No cenário S1 (sem falhas), a latência p95 da variante ISTIO é maior que a da R4J e a do baseline**, por causa do proxy Envoy no caminho de dados.

- Comparação: `p95(istio) > p95(r4j)` e `p95(istio) > p95(baseline)`
- Teste estatístico: Mann-Whitney U, com Cliff's delta para tamanho de efeito

## H2 — Efetividade do retry e circuit breaker

**Nos cenários S3 (erros transitórios 30%) e S4 (erros persistentes 100%), a taxa de sucesso vista pelo cliente não difere significativamente entre ISTIO e R4J.**

- Comparação: `success_rate(istio) ≈ success_rate(r4j)` em S3 e S4
- Teste estatístico: Mann-Whitney U bilateral

## H3 — Tempo de recuperação

**No cenário S5 (recuperação após falha persistente), o tempo de recuperação difere entre ISTIO e R4J.**

- Métrica: tempo entre o `reset` do service-c e o momento em que a taxa de sucesso volta a ficar acima de 99% por 10 s consecutivos
- Comparação: `recovery_time(istio) ≠ recovery_time(r4j)`
- Teste estatístico: Mann-Whitney U bilateral

## H4 — Multiplicação de tentativas (retry storm)

**No cenário S6 (retry no Istio e no Resilience4j simultaneamente), a razão de chamadas ao service-c é maior do que em ISTIO ou R4J isoladas.**

- Métrica: `requests_received_by_c / requests_sent_by_k6`
- Comparação: `ratio(both) > ratio(istio)` e `ratio(both) > ratio(r4j)`
- Teste estatístico: Mann-Whitney U unilateral

## Notas metodológicas

- **Nível de significância:** α = 0.05
- **Repetições:** 5 execuções por combinação cenário × variante
- **Teste não-paramétrico** (Mann-Whitney U / Kruskal-Wallis): escolhido porque o tamanho amostral é pequeno (n=5) e não se assume normalidade
- **Tamanho de efeito:** Cliff's delta (pequeno: |d| < 0.147, médio: < 0.33, grande: ≥ 0.33)
