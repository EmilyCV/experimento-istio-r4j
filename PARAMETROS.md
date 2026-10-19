# Parâmetros correspondentes: Resilience4j × Istio

Os dois mecanismos protegem a **mesma chamada**: `service-a → service-b`.

- **Resilience4j:** configurado em [`services/src/main/resources/application-r4j.yaml`](services/src/main/resources/application-r4j.yaml), ativo só com o profile `r4j`.
- **Istio:** configurado no VirtualService e no DestinationRule do `service-b`, na pasta `k8s/istio/` (Fase 3).

Versões: Spring Boot 3.5.16, Resilience4j 2.4.0 e Istio 1.24.2.

| Parâmetro | Resilience4j | Istio | Valor |
|---|---|---|---|
| Tentativas no total | `max-attempts: 3` (conta a 1ª) | `retries.attempts: 2` (não conta a 1ª) | 3 |
| Em quais erros repetir | `retry-exceptions`: `HttpServerErrorException` (5xx) e `ResourceAccessException` (timeout, falha de conexão) | `retryOn: 5xx,reset,connect-failure` | 5xx, timeout e conexão; nunca 4xx |
| Timeout por tentativa | timeout de leitura do cliente HTTP (`app.http.read-timeout-ms: 500`) | `perTryTimeout: 500ms` | 500 ms |
| Timeout total | — (não existe; o pior caso é 3 × 500 ms + 2 × 25 ms ≈ 1,55 s) | `timeout: 2s` da rota | 2 s |
| Espera entre tentativas | `wait-duration: 25ms` (fixa) | backoff padrão do Envoy (ver abaixo) | 25 ms |
| Circuit breaker | janela de 10 chamadas (`sliding-window-size: 10`, `minimum-number-of-calls: 10`), abre com 50% de falhas, 30 s aberto | `outlierDetection`: `consecutive5xxErrors: 5`, `baseEjectionTime: 30s`, `maxEjectionPercent: 100` | — |
| O que conta como falha no circuit breaker | as mesmas exceções do retry (`record-exceptions`) | respostas 5xx e falhas de conexão vistas pelo sidecar do A | — |
| Timeout de leitura da aplicação | 500 ms (é o timeout por tentativa) | 3 s (maior que o timeout total do Istio, para não ser a aplicação a cortar a chamada) | — |

Na variante `baseline` não há resiliência e o timeout de leitura também é de 3 s. O pool de conexões do cliente HTTP é o mesmo nas três variantes: 100 conexões no total e 50 por destino. Ele fica em [`RestClientConfig.java`](services/src/main/java/com/experiment/resilience/infrastructure/config/RestClientConfig.java).

## Detalhes que a tabela não mostra

**Espera entre tentativas no Istio.** O VirtualService do Istio não tem campo para a espera, então vale o padrão do Envoy, o proxy que roda no sidecar:
- intervalo base de 25 ms e máximo de 250 ms;
- antes da tentativa N, ele espera um tempo sorteado entre 0 e (2^N − 1) × 25 ms (backoff exponencial com *jitter*).

No Resilience4j, a espera é fixa em 25 ms. As duas têm a mesma ordem de grandeza.

**Os circuit breakers não são idênticos.**
- **Istio:** o `outlierDetection` acompanha cada instância (pod) do `service-b`. Depois de 5 erros 5xx seguidos, tira essa instância do balanceamento por 30 s. Como há uma só réplica, as chamadas passam a falhar logo no sidecar, com resposta 503, e o efeito fica parecido com um circuito aberto.
- **Resilience4j:** o circuito fica dentro da aplicação e vale para o destino inteiro. Ele abre pela taxa de falhas numa janela de 10 chamadas e, depois de 30 s, deixa passar 3 chamadas de teste (estado meio-aberto).

Por isso, a linha do circuit breaker tem objetivo equivalente, mas não valores iguais.

**Ordem entre retry e circuit breaker.**
- **Resilience4j:** o retry fica por fora e o circuit breaker por dentro (ordem padrão). Cada tentativa conta no circuit breaker.
- **Istio:** cada tentativa também é uma requisição que pode contar para o `outlierDetection`.

**Retry padrão do Istio nas outras rotas.** Mesmo sem VirtualService, o Istio coloca um retry padrão em toda rota que passa por um sidecar: 2 tentativas extras, só em falhas de conexão (`connect-failure,refused-stream,unavailable,cancelled,retriable-status-codes`). Isso aparece no `istioctl proxy-config route` como uma rota `service-a…` com `numRetries: 2`. Não afeta o experimento, porque o k6 não tem sidecar: a chamada k6 → service-a não passa por nenhum retry. A única política que vale para a chamada A → B é a do nosso VirtualService.

**Sem falhas, nada disso é acionado.** No cenário deste experimento, o `service-b` sempre responde 200 em cerca de 5 ms. Nenhum retry acontece e nenhum circuito abre. Os parâmetros acima garantem que as duas abordagens estão configuradas de forma comparável, mas o teste mede **o custo de ter a resiliência configurada**: o sidecar no caminho contra a biblioteca dentro da aplicação.
