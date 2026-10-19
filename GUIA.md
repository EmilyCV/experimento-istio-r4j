# Guia do experimento: Istio × Resilience4j

Este guia leva você do zero até o `results/RESULTADOS.md`. Ele foi escrito para quem conhece Java, mas sabe pouco de Kubernetes e de Istio. Todos os comandos devem ser rodados no **Git Bash**, na pasta do projeto:

```bash
cd /d/dev/Faculdade/experimento-istio-r4j
```

## Sumário

1. [O que o experimento faz](#1-o-que-o-experimento-faz)
2. [Conceitos em 2 minutos](#2-conceitos-em-2-minutos)
3. [Como o código está organizado](#3-como-o-código-está-organizado)
4. [Pré-requisitos](#4-pré-requisitos)
5. [Passo a passo](#5-passo-a-passo)
6. [Como confirmar que a resiliência está ativa](#6-como-confirmar-que-a-resiliência-está-ativa)
7. [Quanto tempo leva](#7-quanto-tempo-leva)
8. [Desligar e limpar tudo](#8-desligar-e-limpar-tudo)
9. [Erros comuns](#9-erros-comuns)
10. [Decisões de método](#10-decisões-de-método)

---

## 1. O que o experimento faz

Um endpoint chama outro endpoint: o `service-a` (`GET /api/a/{id}`) chama o `service-b` (`GET /api/b/{id}`), que gasta 5 ms de CPU e devolve um JSON. Essa chamada A → B é protegida por **retry + circuit breaker** de três formas, **uma de cada vez**:

| Variante | Resiliência | Sidecar | Papel |
|---|---|---|---|
| `baseline` | nenhuma | não | controle: custo de não ter resiliência |
| `r4j` | Resilience4j, dentro do service-a (`@Retry` e `@CircuitBreaker`) | não | abordagem "na aplicação" |
| `istio` | Istio: VirtualService e DestinationRule | sim, nos dois serviços | abordagem "na infraestrutura" |

```
baseline:   k6 ──► [service-a] ──────────────────────► [service-b]

r4j:        k6 ──► [service-a + Resilience4j] ─────────► [service-b]

istio:      k6 ──► [istio-proxy │ service-a] ──mTLS──► [istio-proxy │ service-b]
                               (retry + circuit breaker no proxy do A)
```

O gerador de carga é o **k6**. Ele roda dentro do cluster, sem sidecar, e envia **20 requisições por segundo, constantes**. Mede-se:

- **a latência vista pelo cliente (p50 e p95):** comportamento temporal, na ISO/IEC 25010;
- **a CPU e a memória de cada container, com o sidecar separado da aplicação:** utilização de recursos.

> **Importante:** o cenário **não tem falhas**: o service-b sempre responde 200. Por isso o retry e o circuit breaker **nunca são acionados**. O experimento mede **o custo de ter a resiliência configurada**: o sidecar no caminho da requisição contra a biblioteca dentro da aplicação. Não mede a resiliência em ação.

As hipóteses e o teste estatístico estão em [`HIPOTESES.md`](HIPOTESES.md). Os parâmetros de resiliência equivalentes estão em [`PARAMETROS.md`](PARAMETROS.md). A modificabilidade é medida à parte, pelo [`ROTEIRO-MODIFICABILIDADE.md`](ROTEIRO-MODIFICABILIDADE.md).

---

## 2. Conceitos em 2 minutos

| Conceito | O que é, em uma frase | Onde aparece aqui |
|---|---|---|
| **Container** | Um processo isolado, criado a partir de uma imagem Docker. | A imagem `resilience-service:1.0` tem o jar Java. |
| **Pod** | A menor unidade do Kubernetes: um ou mais containers que rodam juntos e compartilham rede. | Cada serviço roda num pod. Na variante istio, o pod tem 2 containers: `app` e `istio-proxy`. |
| **Deployment** | Diz ao Kubernetes "mantenha N cópias deste pod rodando, com esta imagem e esta configuração". Se o pod morre, ele recria. | `service-a` e `service-b`, com 1 réplica cada (arquivos `k8s/<variante>/service-*.yaml`). |
| **Service** | Um nome de rede estável que encaminha para os pods certos. É ele que faz `http://service-b:8080` funcionar. | Um Service para cada serviço, no mesmo arquivo do Deployment. |
| **Namespace** | Uma "pasta" dentro do cluster, que separa recursos. Apagar o namespace apaga tudo dentro dele. | Um namespace por variante: `baseline`, `r4j`, `istio`. |
| **kind** | Um cluster Kubernetes inteiro rodando dentro de um container Docker, na sua máquina. | O cluster `exp-cluster`, com um único nó. |
| **Sidecar** | Um container extra colocado ao lado da aplicação no mesmo pod. Todo o tráfego de rede da aplicação passa por ele. | O `istio-proxy` (Envoy), injetado automaticamente nos pods do namespace `istio`. |
| **VirtualService** | Recurso do Istio que diz **como** rotear as chamadas para um destino: timeout, retry etc. | `k8s/istio/virtual-service.yaml`: retry e timeout das chamadas ao service-b. |
| **DestinationRule** | Recurso do Istio que diz **o que fazer com o destino** depois de escolhida a rota: pool de conexões, detecção de instâncias com falha etc. | `k8s/istio/destination-rule.yaml`: o "circuit breaker" (outlier detection) do service-b. |
| **Profile do Spring** | Um nome que ativa um conjunto de configurações e de beans. O Spring carrega `application-<profile>.yaml` e só cria as classes com `@Profile` compatível. | `service-a` ou `service-b` escolhe o papel; `r4j` liga o Resilience4j. Vêm da variável `SPRING_PROFILES_ACTIVE`. |
| **metrics-server** | Componente que coleta CPU e memória dos containers e permite o comando `kubectl top`. | Instalado uma vez; o `rodar-variante.sh` consulta a cada 15 s. |
| **Job** | Um pod que roda uma tarefa até o fim, e não para sempre. | Cada execução do k6 é um Job (`k8s/k6/job-k6.yaml`). |

---

## 3. Como o código está organizado

O projeto Java fica em `services/`. É **um único projeto e uma única imagem**: o papel (A ou B) e a resiliência vêm dos profiles do Spring. O código segue a **Clean Architecture**: o domínio não conhece Spring nem HTTP; os detalhes técnicos ficam na infraestrutura.

```
┌─ infrastructure (Spring MVC, HTTP, Resilience4j) ─────────────────┐
│  entrada: adapter/in/web          saída: adapter/out/rest         │
│    ServiceAController               ServiceBRestAdapter   (!r4j)  │
│    ServiceBController               ServiceBR4jAdapter    (r4j)   │
│    FaultAdminController             config/RestClientConfig       │
│    GlobalExceptionHandler                                         │
└───────────────┬─────────────────────────────────▲─────────────────┘
                │ chama                           │ implementa o port
┌─ application ─▼─────────────────────────────────┼─────────────────┐
│    ServiceAUseCase        ServiceBUseCase       │                 │
└───────────────┬─────────────────────────────────┼─────────────────┘
                │ usa                             │
┌─ domain ──────▼─────────────────────────────────┴─────────────────┐
│    port/out/ServiceBPort  (interface)                             │
│    model: ResponseA, ResponseB, FaultConfig                       │
│    exception: FaultInjectedException                              │
└───────────────────────────────────────────────────────────────────┘
As dependências apontam para dentro: infrastructure → application → domain.
O domain não importa nada do Spring.
```

O que cada classe faz (pacote `com.experiment.resilience`):

| Camada | Classe | Papel |
|---|---|---|
| domain | `ResponseB` | JSON devolvido pelo service-b: `id`, `value` e `cpuTimeMs` (tempo de CPU gasto). |
| domain | `ResponseA` | JSON devolvido pelo service-a: `id`, `status` e a `ResponseB` recebida. |
| domain | `ServiceBPort` | Interface "buscar no service-b". O caso de uso do A depende só dela, sem saber se existe retry. |
| domain | `FaultConfig`, `FaultInjectedException` | Configuração e exceção da injeção de falhas. Não são usadas neste teste e ficam prontas para um teste futuro com falhas. |
| application | `ServiceAUseCase` | Chama o `ServiceBPort` e monta a `ResponseA`. Ativa com o profile `service-a`. |
| application | `ServiceBUseCase` | Ocupa a CPU por `app.cpu-work-ms` (5 ms) e devolve a `ResponseB`. Ativa com o profile `service-b`. |
| infrastructure | `ServiceAController` | Expõe `GET /api/a/{id}` e repassa ao `ServiceAUseCase`. |
| infrastructure | `ServiceBController` | Expõe `GET /api/b/{id}` e repassa ao `ServiceBUseCase`. |
| infrastructure | `FaultAdminController` | `POST /admin/fault` para injetar falhas no B. **Desligado**: só existe com `app.fault-admin.enabled=true`. |
| infrastructure | `GlobalExceptionHandler` | Transforma a falha injetada no código HTTP escolhido (ex.: 503). |
| infrastructure | `ServiceBRestAdapter` | Implementa o port com uma chamada HTTP simples. Ativo em `service-a & !r4j`, ou seja, nas variantes baseline e istio. |
| infrastructure | `ServiceBR4jAdapter` | A mesma chamada, com `@Retry` e `@CircuitBreaker`. Ativo em `service-a & r4j`. |
| infrastructure | `RestClientConfig` | Cria o `RestClient` com o mesmo pool de conexões em todas as variantes. Só o timeout de leitura muda: 500 ms no r4j e 3 s nas outras. |

**Caminho de uma requisição**, de `GET /api/a/42` até o B:

1. O `ServiceAController` recebe a requisição e chama `ServiceAUseCase.execute("42")`.
2. O caso de uso chama `serviceBPort.fetch("42")`. Qual adapter atende depende do profile:
   - **baseline / istio:** `ServiceBRestAdapter` faz `GET http://service-b:8080/api/b/42` uma única vez. Na variante istio, a chamada sai do container pelo `istio-proxy` do A, que aplica o retry e o circuit breaker do VirtualService e do DestinationRule. Ela chega criptografada (mTLS) ao `istio-proxy` do B, que a entrega ao container do B;
   - **r4j:** `ServiceBR4jAdapter` faz a mesma chamada, mas envolvida pelo Resilience4j. Se houver erro 5xx, timeout ou falha de conexão, tenta de novo (até 3 vezes no total) e registra o resultado no circuit breaker.
3. No service-b, o `ServiceBController` chama `ServiceBUseCase.execute("42")`, que gasta 5 ms de CPU e devolve `{"id":"42","value":26.61,"cpuTimeMs":5}`.
4. O service-a devolve `{"id":"42","status":"OK","serviceB":{...}}`.

Arquivos de configuração (`services/src/main/resources/`):

- `application.yaml`: comum a tudo (porta, Actuator, timeouts padrão, CPU do B);
- `application-service-a.yaml`: URL do B, vinda de `APP_SERVICE_B_URL`;
- `application-service-b.yaml`: nome do serviço;
- `application-r4j.yaml`: parâmetros do Resilience4j.

---

## 4. Pré-requisitos

| Ferramenta | Versão usada | Como verificar | O que deve aparecer |
|---|---|---|---|
| Docker Desktop | 4.x, com ~8 GB de memória para o Docker | `docker info --format '{{.MemTotal}}'` | um número perto de 8000000000 (8 GB) |
| kind | v0.33.0 | `kind version` | `kind v0.33.0 ...` |
| kubectl | 1.34 (vem com o Docker Desktop) | `kubectl version --client` | `Client Version: v1.34...` |
| istioctl | 1.24.2 | `istioctl version --remote=false` | `client version: 1.24.2` |
| Java | 21 | `java -version` | `version "21...` |
| Maven | 3.9 | `mvn -v` | `Apache Maven 3.9...` |
| Python | 3.11, com pandas, scipy e matplotlib | `python -c "import pandas, scipy, matplotlib; print('ok')"` | `ok` |

Observações:

- **istioctl:** fica em `C:\tools\istio`. Se o comando `istioctl` não for encontrado, coloque a pasta no PATH da sessão do Git Bash:
  ```bash
  export PATH="/c/tools/istio:$PATH"
  ```
- **Pacotes Python:** se faltar algum, as versões testadas estão em `requirements.txt` (`python -m pip install -r requirements.txt`).
- **Aviso do kubectl:** o kubectl 1.34 com o cluster 1.31 mostra o aviso *"version difference … exceeds the supported minor version skew"*. Pode ignorar: os comandos usados aqui funcionam normalmente.
- **Primeira execução:** baixa da internet as imagens do nó do kind (~400 MB), da base Java, do Istio, do k6 e do metrics-server. Nas próximas, elas já estão no cache.

---

## 5. Passo a passo

### 5.1 Compilar o jar (~1 min)

```bash
mvn -f services/pom.xml clean package -DskipTests
```

- **O que faz:** compila o projeto Java e gera `services/target/resilience-service-1.0.0.jar`.
- **Por quê:** o Dockerfile só copia esse jar para a imagem.
- **Deu certo se:** termina com `BUILD SUCCESS`.
- **Se der erro:** confira `java -version` (precisa ser 21). Erro de download significa que o Maven precisa de internet na primeira vez.

### 5.2 Gerar a imagem Docker (~30 s)

```bash
docker build -t resilience-service:1.0 services
```

- **O que faz:** cria a imagem `resilience-service:1.0`, que é a base Java 21 com o jar dentro.
- **Por quê:** o Kubernetes roda imagens, não jars.
- **Deu certo se:** a última linha tem `naming to docker.io/library/resilience-service:1.0`.
- **Se der erro:** `Cannot connect to the Docker daemon` ou `pipe/dockerDesktopLinuxEngine` significa que o Docker Desktop não está aberto. Abra e espere o ícone ficar verde.

### 5.3 Criar o cluster kind (~1–2 min)

```bash
kind create cluster --name exp-cluster --config k8s/kind-config.yaml
```

- **O que faz:** cria um cluster Kubernetes 1.31.14 com um único nó, dentro de um container Docker. Também configura o `kubectl` para falar com ele.
- **Por quê:** o Istio 1.24.2 só suporta Kubernetes de 1.28 a 1.31. Por isso a imagem do nó está fixada em `k8s/kind-config.yaml`.
- **Deu certo se:** aparece `Set kubectl context to "kind-exp-cluster"`. Depois, `kubectl get nodes` mostra `exp-cluster-control-plane   Ready`. Ele pode aparecer como `NotReady` nos primeiros 20 s.
- **Se der erro:** `node(s) already exist for a cluster with the name "exp-cluster"` significa que o cluster já existe. Pule este passo ou apague antes com `kind delete cluster --name exp-cluster`.

### 5.4 Carregar a imagem no cluster (~30 s)

```bash
kind load docker-image resilience-service:1.0 --name exp-cluster
```

- **O que faz:** copia a imagem do seu Docker para dentro do nó do kind.
- **Por quê:** o cluster não enxerga as imagens do seu Docker e não deve baixá-las da internet. Os YAML usam `imagePullPolicy: IfNotPresent`.
- **Deu certo se:** aparece `Image: "resilience-service:1.0" ... loading...` e o comando termina sem erro.
- **Atenção:** se você mudar o código, repita os passos 5.1, 5.2 e 5.4.

### 5.5 Instalar o metrics-server (~1 min)

```bash
kubectl apply -f k8s/metrics-server/components.yaml
```
```bash
kubectl -n kube-system rollout status deployment/metrics-server
```
```bash
kubectl top node
```

- **O que faz:** instala o coletor de CPU e memória (v0.8.1). O arquivo é o oficial, com uma opção a mais, `--kubelet-insecure-tls`, que o kind exige.
- **Por quê:** o `rodar-variante.sh` usa o `kubectl top pod --containers` para medir os recursos.
- **Deu certo se:** o `kubectl top node` mostra uma linha com `CPU(cores)` e `MEMORY(bytes)`.
- **Se der erro:** `error: Metrics API not available` aparece quando ele acabou de subir. Espere 30 a 60 s e repita.

### 5.6 Instalar o Istio (~1 min)

```bash
istioctl install --set profile=minimal -y
```
```bash
kubectl -n istio-system get pods
```

- **O que faz:** instala o Istio 1.24.2 no perfil `minimal`. Isso significa só o `istiod`, o plano de controle, que configura os sidecars, mais as definições de VirtualService e DestinationRule. Não instala gateways.
- **Por quê:** a variante istio precisa dele. Ele fica instalado também durante as outras variantes (ver seção 10).
- **Deu certo se:** aparecem `✔ Installation complete` e um pod `istiod-...   1/1   Running`.
- **Se der erro:** `istioctl: command not found` significa que falta o PATH (ver seção 4).

### 5.7 Apagar os resultados de teste (~5 s)

O `rodar-variante.sh` **não sobrescreve** resultados. Se `results/` tiver dados de execuções anteriores, como os testes curtos de validação, apague-os antes:

```bash
rm -rf results/baseline results/r4j results/istio results/RESULTADOS.md results/boxplot_*.png
```

### 5.8 (Opcional) Teste rápido de uma variante (~2 min)

```bash
./rodar-variante.sh baseline 2 15
```

Serve para conferir que tudo está no ar antes de gastar uma hora. Depois de rodar, **apague a pasta gerada** (`rm -rf results/baseline`).

### 5.9 Rodar as três variantes (~19 min cada, ~1 h no total)

```bash
./rodar-variante.sh baseline
```
```bash
./rodar-variante.sh r4j
```
```bash
./rodar-variante.sh istio
```

- **O que faz:** para cada variante:
  1. sobe os dois serviços (`kubectl apply -f k8s/<variante>/`) e espera ficarem prontos;
  2. roda **30 s de aquecimento** com o k6, que são descartados. O aquecimento existe porque a JVM é lenta nas primeiras requisições, até o compilador JIT otimizar o código;
  3. roda **10 repetições de 90 s** a 20 req/s, com 10 s de pausa entre elas. Em cada uma:
     - grava `results/<variante>/rep<N>.json` com a latência medida pelo k6;
     - coleta CPU e memória a cada 15 s em `results/<variante>/rep<N>-recursos.csv`;
  4. remove a variante do cluster.
- **Parâmetros opcionais:** `./rodar-variante.sh <variante> [repeticoes] [duracao_s]`. A taxa muda com `TAXA=30 ./rodar-variante.sh r4j`.
- **Deu certo se:** cada repetição imprime uma linha como
  ```
  [21:24:55]     -> p95 = 10.47 ms | sucesso = 1 | 18 linhas de recursos
  ```
  e o final é `=== Pronto. Resultados em results/<variante>/ ===`. `sucesso = 1` significa 100% das requisições com HTTP 200.
- **Dicas:**
  - não use o computador para tarefas pesadas durante a execução, porque isso afeta as medidas;
  - deixe o notebook na tomada;
  - rode as três variantes em seguida, nas mesmas condições.
- **Se der erro:** ver a seção 9. O script remove a variante sozinho se algo falhar ou se você apertar Ctrl+C. Antes de rodar de novo, apague a pasta `results/<variante>` incompleta.

### 5.10 Rodar a análise (~10 s)

```bash
python analise.py
```

- **O que faz:** lê todos os resultados e roda os testes de Mann-Whitney com o δ de Cliff. Gera o `results/RESULTADOS.md` e dois gráficos, `results/boxplot_p95.png` e `results/boxplot_cpu.png`.
- **Deu certo se:** imprime `Repetições lidas: 30` e `Gerados: results/RESULTADOS.md, ...`, sem linhas `AVISO:`.

### 5.11 Conferir os resultados

Abra o `results/RESULTADOS.md` e confira, na seção "Condições da execução":

- 10 repetições em cada variante;
- "Menor taxa de sucesso" igual a 100,00% em todas;
- "Iterações descartadas" igual a 0 em todas (o k6 conseguiu manter os 20 req/s);
- nenhuma seção "Avisos".

Se algo disso falhar, os dados daquela variante não servem: apague a pasta e rode a variante de novo.

---

## 6. Como confirmar que a resiliência está ativa

Útil para a monografia e para o roteiro de modificabilidade. Suba a variante manualmente e, no fim, remova:

```bash
kubectl apply -f k8s/r4j/
```
```bash
kubectl delete -f k8s/r4j/
```

**Resilience4j (variante r4j).** Os endpoints do Actuator do service-a são chamados de dentro do cluster, a partir do pod do service-b, que tem `wget`:

```bash
kubectl -n r4j exec deploy/service-b -- wget -qO- http://service-a:8080/actuator/retries
```
```bash
kubectl -n r4j exec deploy/service-b -- wget -qO- http://service-a:8080/actuator/circuitbreakers
```
```bash
kubectl -n r4j exec deploy/service-b -- wget -qO- http://service-a:8080/actuator/configprops/resilience4j.retry
```

| Comando | O que deve aparecer |
|---|---|
| `/actuator/retries` | `{"retries":["serviceB"]}` |
| `/actuator/circuitbreakers` | `"serviceB":{... "state":"CLOSED"}` |
| `/actuator/configprops/resilience4j.retry` | `"maxAttempts":3`, `"waitDuration":"PT0.025S"` e as duas exceções |

**Istio (variante istio).** Primeiro, descubra o nome do pod do service-a e veja a política que o sidecar dele recebeu para a rota do service-b:

```bash
POD=$(kubectl -n istio get pod -l app=service-a -o jsonpath='{.items[0].metadata.name}')
```
```bash
istioctl proxy-config route $POD.istio --name 8080 -o json | grep -A25 '"name": "service-b.istio' | grep -E 'retryOn|numRetries|perTryTimeout'
```

Deve aparecer `"retryOn": "5xx,reset,connect-failure"`, `"numRetries": 2` e `"perTryTimeout": "0.500s"`.

Para ver o circuit breaker (outlier detection):

```bash
istioctl proxy-config cluster $POD.istio --fqdn service-b.istio.svc.cluster.local -o json | grep -A8 outlierDetection
```

Deve aparecer `consecutive5xx: 5`, `baseEjectionTime: 30s` e `maxEjectionPercent: 100`.

Para conferir que os dois pods têm sidecar:

```bash
kubectl -n istio get pods
```

A coluna READY deve mostrar `2/2`: a aplicação mais o `istio-proxy`.

---

## 7. Quanto tempo leva

| Etapa | Tempo aproximado |
|---|---|
| 5.1 a 5.4: compilar, gerar a imagem, criar o cluster, carregar a imagem | 3–5 min (mais na primeira vez, por causa dos downloads) |
| 5.5 e 5.6: metrics-server e Istio | 2 min |
| 5.8: teste rápido (opcional) | 2 min |
| 5.9: cada variante (subir + 30 s de aquecimento + 10 × (90 s + pausa) + remover) | ~19 min |
| 5.9: as três variantes | ~1 h |
| 5.10: análise | 10 s |
| **Total, do zero** | **~1 h 15 min** |

---

## 8. Desligar e limpar tudo

Ao terminar, guarde os resultados (eles entram no git) e apague o cluster:

```bash
kind delete cluster --name exp-cluster
```

Isso remove o cluster inteiro, inclusive o Istio, o metrics-server e as imagens carregadas nele. Para recomeçar, volte ao passo 5.3.

Para liberar espaço em disco, também dá para apagar as imagens Docker:

```bash
docker image rm resilience-service:1.0
```

Feche o Docker Desktop se não for usar mais: ele reserva memória mesmo parado.

---

## 9. Erros comuns

| Mensagem ou sintoma | Causa provável | O que fazer |
|---|---|---|
| `error during connect ... dockerDesktopLinuxEngine` | Docker Desktop fechado ou ainda iniciando | Abrir o Docker Desktop e esperar ~1 min. |
| `The connection to the server ... was refused` | Cluster apagado ou Docker reiniciado | `kind get clusters`; se não aparecer `exp-cluster`, voltar ao passo 5.3. |
| `ERRO: o metrics-server não está respondendo` | metrics-server não instalado ou recém-instalado | Passo 5.5; esperar 1 min. |
| `ERRO: a variante 'X' já está no cluster` | Uma execução anterior foi interrompida | `kubectl delete -f k8s/X/` e rodar de novo. |
| `ERRO: a pasta results/X já tem arquivos` | Proteção contra sobrescrever dados | Mover ou apagar a pasta (passo 5.7). |
| Pod em `ErrImageNeverPull` ou `ErrImagePull` | Imagem não carregada no kind | Passo 5.4. |
| Pod em `CrashLoopBackOff` | Erro ao subir o Spring | `kubectl logs -n <variante> deploy/service-a -c app` para ver o erro. |
| Pod `0/1` ou `1/2` por muito tempo | O Spring ainda está subindo (até 2 min é normal no kind) | `kubectl -n <variante> get pods -w` e aguardar. |
| `sucesso = 0.98` (menor que 1) | Erros nas requisições | Ver os logs do service-a; repetir a variante. |
| `iteracoes_descartadas` > 0 no JSON | A máquina não deu conta da taxa | Fechar outros programas e repetir. Se persistir, reduzir a taxa (`TAXA=15`) para **todas** as variantes. |
| `$'\r': command not found` ao rodar o `.sh` | Script com quebra de linha do Windows | `sed -i 's/\r$//' rodar-variante.sh` (o `.gitattributes` evita isso). |

---

## 10. Decisões de método

Escolhas que valem registrar na monografia:

- **Uma variante de cada vez.** Cada variante é criada, medida e removida antes da próxima, para que não disputem a CPU do nó.
- **O mesmo ambiente para as três.** O `istiod` e o metrics-server ficam instalados durante todas as variantes. Só a variante istio tem sidecars. O `istiod` não entra no "total" das hipóteses, mas aparece descritivamente no relatório.
- **k6 dentro do cluster, sem sidecar.** Assim se evita o `port-forward`, que acrescenta latência e distorce a medida. A anotação `sidecar.istio.io/inject: "false"` garante que o cliente não tenha proxy.
- **Aquecimento separado (30 s, descartado).** A JVM é lenta nas primeiras requisições. O aquecimento é uma execução própria do k6, não fica no `setup()`.
- **Recursos iguais para a aplicação.** Em todas as variantes: CPU de 1 core e memória de 512 Mi, com `requests = limits`. O sidecar usa os valores padrão do Istio (requests de 100m e 128 Mi; limits de 2 CPU e 1 Gi).
- **mTLS no padrão do Istio (PERMISSIVE).** Entre os dois sidecars, o tráfego é criptografado automaticamente. Isso faz parte do custo medido do sidecar. O k6, sem sidecar, fala com o service-a em texto puro, o que o modo PERMISSIVE aceita.
- **Atraso do `kubectl top`.** O metrics-server mostra a média dos últimos ~15 s, com 10 a 25 s de atraso (verificado no teste). Por isso, a análise descarta as amostras de recursos dos primeiros 30 s de cada repetição.
- **Repetições no mesmo deploy.** As 10 repetições de uma variante rodam sobre os mesmos pods, sem reiniciar. Isso é mais simples e mais rápido, mas as repetições não são totalmente independentes, e isso é citado nas limitações.

**Versões utilizadas**

| Componente | Versão |
|---|---|
| Java (imagem) | Eclipse Temurin 21.0.12.1, imagem `eclipse-temurin:21-jre-alpine@sha256:51ab5e33…` |
| Spring Boot | 3.5.16 |
| Resilience4j | 2.4.0 |
| Kubernetes (kind) | 1.31.14 (`kindest/node:v1.31.14@sha256:6f86cf50…`), kind v0.33.0 |
| Istio | 1.24.2, perfil minimal, modo sidecar |
| metrics-server | 0.8.1 |
| k6 | 2.2.0 (imagem `grafana/k6:2.2.0`) |
| Python | 3.11, pandas 2.3.3, scipy 1.16.3, matplotlib 3.10.0 |
