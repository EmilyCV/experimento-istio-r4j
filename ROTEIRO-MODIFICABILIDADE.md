# Roteiro de modificabilidade

Roteiro manual, sem estatística, para comparar o **esforço de mudar um parâmetro de retry** em cada abordagem. Ele mede a **modificabilidade**, subcaracterística da **manutenibilidade** na ISO/IEC 25010: o grau em que um produto pode ser modificado de forma eficaz e eficiente, sem introduzir defeitos nem degradar a qualidade existente.

## A tarefa

**Mudar o retry de 3 para 2 tentativas no total**, uma vez em cada abordagem, e confirmar que a mudança está valendo.

| Abordagem | Onde fica o parâmetro | De → para |
|---|---|---|
| Resilience4j | `services/src/main/resources/application-r4j.yaml` | `max-attempts: 3` → `max-attempts: 2` |
| Istio | `k8s/istio/virtual-service.yaml` | `attempts: 2` → `attempts: 1` |

As duas linhas significam a mesma coisa (ver `PARAMETROS.md`): o Resilience4j conta a primeira tentativa, e o Istio conta só as repetições.

## Regras para cronometrar

- **Pré-requisitos:** o cluster, o metrics-server e o Istio no ar (passos 5.1 a 5.6 do `GUIA.md`). Nenhuma outra variante pode estar rodando.
- **O cronômetro começa** quando você abre o arquivo para editar e **para** quando o comando de confirmação mostra o novo valor.
- **Não entra no tempo:** subir a variante antes, voltar o valor original depois e remover a variante.
- **Repita 3 vezes cada abordagem.** Entre uma tentativa e outra, volte o valor original (3 no Resilience4j, 2 no Istio), seguindo os mesmos passos, sem cronometrar.
- **Use sempre o mesmo editor** e deixe os comandos à mão (copiar e colar deste arquivo), para que as diferenças venham da abordagem e não da digitação.

---

## Abordagem 1: Resilience4j

**Preparação (fora do tempo):**

```bash
kubectl apply -f k8s/r4j/
```
```bash
kubectl -n r4j rollout status deployment/service-a
```

Confirme que o valor inicial é 3:

```bash
kubectl -n r4j exec deploy/service-b -- wget -qO- http://service-a:8080/actuator/configprops/resilience4j.retry | grep -o '"maxAttempts":[0-9]*' | head -1
```

Deve aparecer `"maxAttempts":3`.

**Início do cronômetro.**

1. **Editar** `services/src/main/resources/application-r4j.yaml`: trocar `max-attempts: 3` por `max-attempts: 2` e salvar.
2. **Recompilar o jar:**
   ```bash
   mvn -f services/pom.xml clean package -DskipTests
   ```
3. **Gerar a imagem de novo:**
   ```bash
   docker build -t resilience-service:1.0 services
   ```
4. **Carregar a imagem no kind:**
   ```bash
   kind load docker-image resilience-service:1.0 --name exp-cluster
   ```
5. **Reiniciar o pod do service-a**, para ele subir com a imagem nova:
   ```bash
   kubectl -n r4j rollout restart deployment/service-a
   ```
   ```bash
   kubectl -n r4j rollout status deployment/service-a
   ```
6. **Confirmar pelo Actuator:**
   ```bash
   kubectl -n r4j exec deploy/service-b -- wget -qO- http://service-a:8080/actuator/configprops/resilience4j.retry | grep -o '"maxAttempts":[0-9]*' | head -1
   ```
   Deve aparecer `"maxAttempts":2`.

**Fim do cronômetro.**

Na validação, os comandos 2 a 6 levaram cerca de 30 s, sem contar a edição.

**Voltar ao original (fora do tempo):** repita os passos 1 a 5 com `max-attempts: 3`. Depois da 3ª tentativa, remova a variante:

```bash
kubectl delete -f k8s/r4j/
```

> **Observação para a monografia:** neste experimento, a configuração do Resilience4j fica **dentro do artefato** (o `application-r4j.yaml` vai para o jar). Por isso a mudança exige recompilar, gerar a imagem e reiniciar o pod. O Spring também permitiria sobrescrever o valor no YAML do Kubernetes, por exemplo com a variável `SPRING_APPLICATION_JSON='{"resilience4j":{"retry":{"instances":{"serviceB":{"max-attempts":2}}}}}'`. Assim não seria preciso recompilar, mas o pod ainda precisaria reiniciar. O roteiro usa o caminho em que a configuração mora junto do código, que é o modelo adotado no projeto. Vale citar essa alternativa ao discutir os resultados.

---

## Abordagem 2: Istio

**Preparação (fora do tempo):**

```bash
kubectl apply -f k8s/istio/
```
```bash
kubectl -n istio rollout status deployment/service-a
```
```bash
POD=$(kubectl -n istio get pod -l app=service-a -o jsonpath='{.items[0].metadata.name}')
```

Confirme que o valor inicial é 2:

```bash
istioctl proxy-config route $POD.istio --name 8080 -o json | grep -A25 '"name": "service-b.istio' | grep numRetries
```

Deve aparecer `"numRetries": 2,`.

**Início do cronômetro.**

1. **Editar** `k8s/istio/virtual-service.yaml`: trocar `attempts: 2` por `attempts: 1` e salvar.
2. **Aplicar no cluster:**
   ```bash
   kubectl apply -f k8s/istio/virtual-service.yaml
   ```
   Deve aparecer `virtualservice.networking.istio.io/service-b configured`.
3. **Confirmar no sidecar do service-a.** O `istiod` envia a nova configuração ao proxy em cerca de 1 s, sem reiniciar nada:
   ```bash
   istioctl proxy-config route $POD.istio --name 8080 -o json | grep -A25 '"name": "service-b.istio' | grep numRetries
   ```
   Deve aparecer `"numRetries": 1,`.

**Fim do cronômetro.**

Atenção: use o `grep -A25 '"name": "service-b.istio'` do comando. Sem ele, aparece também um `numRetries: 2` de outra rota, que é o retry padrão do Istio para o próprio service-a (ver `PARAMETROS.md`).

**Voltar ao original (fora do tempo):** repita os passos 1 a 3 com `attempts: 2`. Depois da 3ª tentativa, remova a variante:

```bash
kubectl delete -f k8s/istio/
```

---

## Tabela para preencher

Para contar as linhas alteradas, rode `git diff --stat` logo depois da edição, antes de voltar o valor.

| Abordagem | Tentativa | Arquivos alterados | Linhas alteradas | Precisou recompilar? | Precisou reiniciar pod? | Tempo até a mudança confirmada (mm:ss) |
|---|---|---|---|---|---|---|
| Resilience4j | 1 | | | | | |
| Resilience4j | 2 | | | | | |
| Resilience4j | 3 | | | | | |
| Istio | 1 | | | | | |
| Istio | 2 | | | | | |
| Istio | 3 | | | | | |

**Resultado esperado**, para conferir o que você anotar:
- **Resilience4j:** 1 arquivo, 1 linha; recompila (Maven + imagem + `kind load`) e reinicia o pod do service-a.
- **Istio:** 1 arquivo, 1 linha; não recompila e não reinicia nada (só `kubectl apply`).

O tempo é o que diferencia as duas.

## Como relatar

Para cada abordagem, informe a mediana dos 3 tempos e descreva os passos necessários. Lembre que isso **não é um teste estatístico**: com 3 medidas e uma única pessoa executando, o resultado é descritivo. Ele mostra o esforço de mudança em cada abordagem, ligado à **modificabilidade** da ISO/IEC 25010.
