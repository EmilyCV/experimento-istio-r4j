# Hipóteses do experimento

## O que se compara

Duas formas de aplicar **retry + circuit breaker** na chamada `service-a → service-b`:

- **Resilience4j (variante `r4j`):** uma biblioteca dentro da aplicação Java, sem sidecar.
- **Istio (variante `istio`):** um sidecar Envoy ao lado de cada serviço, com a política declarada em YAML. O código não tem resiliência.

A variante `baseline`, sem resiliência e sem sidecar, serve só de referência descritiva e não entra nos testes.

O cenário **não tem falhas**: o retry e o circuit breaker nunca são acionados. Por isso, as hipóteses tratam do **custo de ter a resiliência configurada**, e não do comportamento dela diante de falhas.

## Fundamentação

Zhu et al. (2023) mostram que o sidecar de um service mesh acrescenta latência e consumo de recursos a cada requisição. No Istio, cada chamada atravessa dois proxies a mais: o do serviço que chama e o do serviço chamado. O tráfego entre eles também é criptografado com mTLS. No Resilience4j, a lógica fica dentro do processo Java, sem proxy no caminho. Daí a expectativa de que o Istio custe mais. As hipóteses são, por isso, **unilaterais**.

## Hipóteses

Característica de qualidade da ISO/IEC 25010: **eficiência de desempenho**.

| | Subcaracterística | Hipótese nula (H0) | Hipótese alternativa (H1) |
|---|---|---|---|
| **H1** | Comportamento temporal | A latência p95 do Istio é igual à do Resilience4j. | A latência p95 do Istio é **maior**. |
| **H2** | Utilização de recursos (CPU) | A CPU total da variante Istio é igual à da variante Resilience4j. | A CPU total do Istio é **maior**. |
| **H3** | Utilização de recursos (memória) | A memória total da variante Istio é igual à da variante Resilience4j. | A memória total do Istio é **maior**. |

**O que conta como "total":** a soma dos containers dos dois serviços (service-a e service-b).
- Na variante `istio`: a aplicação mais o sidecar `istio-proxy` de cada pod.
- Na variante `r4j`: só a aplicação.

Ficam de fora:
- **O `istiod`:** é o plano de controle do Istio, um custo fixo, compartilhado por todo o mesh e fora do caminho da requisição. Ele é mostrado à parte, só descritivamente.
- **O pod do k6:** é o gerador de carga.

## Unidade de análise

A unidade é a **repetição**. Cada variante roda 10 repetições de 90 s a 20 req/s, e cada repetição gera um valor de cada medida:
- **latência p95:** o percentil 95 das requisições daquela repetição, medido pelo k6;
- **CPU e memória:** a média das amostras do `kubectl top`, coletadas a cada 15 s. As amostras dos primeiros 30 s são descartadas porque o metrics-server responde com atraso. Em cada amostra, os containers são somados conforme a definição de "total" acima.

## Teste estatístico

- **Teste:** Mann-Whitney U, unilateral (`alternative="greater"`: Istio > Resilience4j). É um teste não paramétrico: não exige que os dados sigam uma distribuição normal, o que é adequado para amostras pequenas (10 por grupo) e para latências, que costumam ser assimétricas.
- **Nível de significância:** α = 0,05, com **correção de Bonferroni** para as 3 hipóteses. Cada hipótese é testada com α ajustado = 0,05 / 3 ≈ **0,0167**. A correção é necessária porque, ao fazer vários testes, cresce a chance de encontrar pelo menos um resultado "significativo" por acaso. Dividir o α pelo número de testes mantém essa chance total em até 5%.
- **Tamanho de efeito:** δ (delta) de Cliff, que vai de −1 a +1. Ele mede com que frequência um valor do Istio é maior que um do Resilience4j, menos a frequência do contrário. A interpretação segue Romano et al. (2006):

| \|δ\| | Interpretação |
|---|---|
| < 0,147 | desprezível |
| < 0,33 | pequeno |
| < 0,474 | médio |
| ≥ 0,474 | grande |

O p-valor responde se a diferença é estatisticamente significativa. O δ de Cliff responde se ela é grande ou pequena. Os dois são relatados juntos.

## O que fica fora das hipóteses

- **Comparações com o `baseline`:** aparecem no `results/RESULTADOS.md` só como descrição (diferença em valor absoluto e em %), para mostrar o custo de cada abordagem em relação a não ter resiliência.
- **Modificabilidade (ISO/IEC 25010, manutenibilidade):** é avaliada pelo roteiro manual em [`ROTEIRO-MODIFICABILIDADE.md`](ROTEIRO-MODIFICABILIDADE.md), sem teste estatístico.

## Referências

- ZHU, X. et al. (2023). *Referência completa a preencher na monografia.*
- ROMANO, J. et al. (2006). *Appropriate statistics for ordinal level data: Should we really be using t-test and Cohen's d for evaluating group differences on the NSSE and other surveys?* Annual meeting of the Florida Association of Institutional Research.
