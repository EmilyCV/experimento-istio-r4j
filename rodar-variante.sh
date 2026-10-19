#!/usr/bin/env bash
#
# rodar-variante.sh — executa UMA variante do experimento, do início ao fim.
#
# Uso:
#   ./rodar-variante.sh <variante> [repeticoes] [duracao_em_segundos]
#
#   variante    baseline, r4j ou istio
#   repeticoes  número de repetições medidas (padrão: 10)
#   duracao     duração de cada repetição em segundos (padrão: 90)
#
# A taxa de carga vem da variável TAXA (padrão: 20 requisições por segundo):
#   TAXA=30 ./rodar-variante.sh r4j
#
# O que o script faz:
#   1. sobe a variante (kubectl apply -f k8s/<variante>/) e espera ficar pronta;
#   2. roda um aquecimento de 30 s com o k6 (resultado descartado);
#   3. roda as repetições; em cada uma, guarda:
#        results/<variante>/rep<N>.json          resumo de latência do k6
#        results/<variante>/rep<N>-recursos.csv  CPU e memória a cada 15 s
#        results/<variante>/execucao.txt         parâmetros usados nesta execução
#   4. remove a variante do cluster (também se der erro ou Ctrl+C).
#
# Pré-requisitos: cluster kind no ar, imagem carregada, metrics-server instalado
# e, para a variante istio, o Istio instalado (ver GUIA.md).

set -euo pipefail

# ---------------------------------------------------------------- parâmetros
VARIANTE="${1:-}"
REPETICOES="${2:-10}"
DURACAO_S="${3:-90}"
TAXA="${TAXA:-20}"

AQUECIMENTO_S=30            # duração do aquecimento (descartado)
INTERVALO_COLETA_S=15       # de quanto em quanto tempo coleta CPU e memória
PAUSA_ENTRE_REPS_S=10       # descanso entre repetições

# Pasta do projeto (onde este script está), para funcionar de qualquer lugar.
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASTA_RESULTADOS="$RAIZ/results/$VARIANTE"

# ---------------------------------------------------------------- funções
log() { echo "[$(date +%H:%M:%S)] $*"; }
erro() { echo "[$(date +%H:%M:%S)] ERRO: $*" >&2; exit 1; }

# Remove a variante do cluster. Chamada no fim e também se o script parar no meio.
PID_COLETA=""
limpar() {
  if [[ -n "$PID_COLETA" ]]; then kill "$PID_COLETA" 2>/dev/null || true; fi
  if kubectl get namespace "$VARIANTE" >/dev/null 2>&1; then
    log "Removendo a variante '$VARIANTE' do cluster (pode levar até 1 min)..."
    kubectl delete -f "$RAIZ/k8s/$VARIANTE/" --wait=true >/dev/null 2>&1 || true
    log "Variante removida."
  fi
}

# Coleta CPU e memória de todos os containers da variante (e do istiod)
# a cada INTERVALO_COLETA_S segundos, até ser interrompida.
# Formato do "kubectl top pod --containers --no-headers":  POD  CONTAINER  CPU  MEMÓRIA
# Exemplo (aos 45 s): service-a-7d9f  app  35m  210Mi  ->  service-a-7d9f,app,35,210,45
#
# A coluna "segundos" é o tempo desde o início da carga. Ela existe porque o
# metrics-server mostra a média dos últimos ~15 s e com atraso de 10 a 25 s:
# as amostras dos primeiros 30 s ainda misturam o período sem carga, e a
# análise (analise.py) as descarta.
coletar_recursos() {
  local arquivo="$1" inicio=$SECONDS
  echo "pod,container,cpu_milicores,memoria_mib,segundos" > "$arquivo"
  while true; do
    sleep "$INTERVALO_COLETA_S"
    {
      kubectl top pod -n "$VARIANTE" --containers --no-headers 2>/dev/null || true
      kubectl top pod -n istio-system --containers --no-headers 2>/dev/null || true
    } | tr -d '\r' | awk -v seg=$(( SECONDS - inicio )) '
        $1 ~ /^k6-/ { next }                       # o gerador de carga não entra na medida
        NF == 4 {
          cpu = $3; mem = $4
          if (cpu ~ /m$/) { sub(/m$/, "", cpu) } else { cpu = cpu * 1000 }   # núcleos -> milicores
          if (mem ~ /Mi$/)      { sub(/Mi$/, "", mem) }
          else if (mem ~ /Gi$/) { sub(/Gi$/, "", mem); mem = mem * 1024 }
          else if (mem ~ /Ki$/) { sub(/Ki$/, "", mem); mem = mem / 1024 }
          print $1 "," $2 "," cpu "," mem "," seg
        }' >> "$arquivo"
  done
}

# Cria um Job do k6 e espera o pod começar a rodar.
# Argumentos: nome do Job, rótulo, duração em segundos.
rodar_k6() {
  local nome="$1" rotulo="$2" duracao="$3"

  kubectl delete job "$nome" -n "$VARIANTE" --ignore-not-found >/dev/null
  sed -e "s/__NOME__/$nome/" \
      -e "s/__VARIANTE__/$VARIANTE/" \
      -e "s/__ROTULO__/$rotulo/" \
      -e "s/__TAXA__/$TAXA/" \
      -e "s/__DURACAO__/${duracao}s/" \
      "$RAIZ/k8s/k6/job-k6.yaml" | kubectl apply -n "$VARIANTE" -f - >/dev/null

  # Espera o pod do k6 começar a rodar.
  local inicio=$SECONDS fase=""
  while true; do
    fase=$(kubectl get pod -n "$VARIANTE" -l job-name="$nome" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
    [[ "$fase" == "Running" || "$fase" == "Succeeded" || "$fase" == "Failed" ]] && break
    (( SECONDS - inicio > 120 )) && erro "o pod do k6 ($nome) não começou em 2 min. Veja: kubectl describe pod -n $VARIANTE -l job-name=$nome"
    sleep 1
  done
}

# Espera o Job do k6 terminar e guarda o log em $LOG_K6.
esperar_k6() {
  local nome="$1" duracao="$2"
  local limite=$(( duracao + 120 ))   # tempo máximo de espera, com folga
  local inicio=$SECONDS ok falhou
  while true; do
    ok=$(kubectl get job "$nome" -n "$VARIANTE" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
    falhou=$(kubectl get job "$nome" -n "$VARIANTE" -o jsonpath='{.status.failed}' 2>/dev/null || true)
    [[ "$ok" == "1" ]] && break
    [[ -n "$falhou" && "$falhou" != "0" ]] && { kubectl logs -n "$VARIANTE" "job/$nome" | tail -20 >&2; erro "o k6 ($nome) falhou (log acima)."; }
    (( SECONDS - inicio > limite )) && erro "o k6 ($nome) passou de ${limite}s sem terminar."
    sleep 2
  done
  LOG_K6="$(kubectl logs -n "$VARIANTE" "job/$nome" | tr -d '\r')"
}

# ---------------------------------------------------------------- verificações
case "$VARIANTE" in
  baseline|r4j|istio) ;;
  *) erro "variante inválida: '$VARIANTE'. Use: baseline, r4j ou istio. Ex.: ./rodar-variante.sh r4j 10 90" ;;
esac
[[ "$REPETICOES" =~ ^[0-9]+$ && "$REPETICOES" -ge 1 ]] || erro "repetições deve ser um número >= 1."
[[ "$DURACAO_S" =~ ^[0-9]+$ && "$DURACAO_S" -ge 10 ]] || erro "duração deve ser um número de segundos >= 10."

kubectl get nodes >/dev/null 2>&1 || erro "não consegui falar com o cluster. O Docker Desktop e o cluster kind estão no ar? (kind get clusters)"
kubectl top node >/dev/null 2>&1 || erro "o metrics-server não está respondendo (kubectl top node). Ver GUIA.md."
if [[ "$VARIANTE" == "istio" ]]; then
  kubectl get deployment istiod -n istio-system >/dev/null 2>&1 || erro "o Istio não está instalado (ver GUIA.md)."
fi

# Uma variante de cada vez: não pode haver outra no cluster.
for outra in baseline r4j istio; do
  if kubectl get namespace "$outra" >/dev/null 2>&1; then
    erro "a variante '$outra' já está no cluster. Remova antes: kubectl delete -f k8s/$outra/"
  fi
done

# Não sobrescreve resultados antigos.
if [[ -d "$PASTA_RESULTADOS" ]] && [[ -n "$(ls -A "$PASTA_RESULTADOS" 2>/dev/null)" ]]; then
  erro "a pasta $PASTA_RESULTADOS já tem arquivos. Mova ou apague antes de rodar de novo."
fi
mkdir -p "$PASTA_RESULTADOS"

trap limpar EXIT

# ---------------------------------------------------------------- execução
log "=== Variante: $VARIANTE | $REPETICOES repetições de ${DURACAO_S}s | $TAXA req/s ==="

log "1/4 Subindo a variante (kubectl apply -f k8s/$VARIANTE/)..."
kubectl apply -f "$RAIZ/k8s/$VARIANTE/" >/dev/null
kubectl apply -n "$VARIANTE" -f "$RAIZ/k8s/k6/script-k6.yaml" >/dev/null
log "    Esperando os pods ficarem prontos (o Spring leva ~15 s)..."
kubectl rollout status deployment/service-b -n "$VARIANTE" --timeout=300s >/dev/null
kubectl rollout status deployment/service-a -n "$VARIANTE" --timeout=300s >/dev/null
kubectl get pods -n "$VARIANTE" -o custom-columns='    POD:.metadata.name,CONTAINERS:.spec.containers[*].name'

# Registra como a execução foi feita, para conferência posterior.
{
  echo "variante=$VARIANTE"
  echo "repeticoes=$REPETICOES"
  echo "duracao_s=$DURACAO_S"
  echo "taxa_rps=$TAXA"
  echo "aquecimento_s=$AQUECIMENTO_S"
  echo "intervalo_coleta_s=$INTERVALO_COLETA_S"
  echo "inicio=$(date '+%Y-%m-%d %H:%M:%S')"
} > "$PASTA_RESULTADOS/execucao.txt"

log "2/4 Aquecimento de ${AQUECIMENTO_S}s (resultado descartado)..."
rodar_k6 k6-aquecimento aquecimento "$AQUECIMENTO_S"
esperar_k6 k6-aquecimento "$AQUECIMENTO_S"
kubectl delete job k6-aquecimento -n "$VARIANTE" >/dev/null
log "    Aquecimento concluído."

log "3/4 Repetições medidas..."
for (( n = 1; n <= REPETICOES; n++ )); do
  sleep "$PAUSA_ENTRE_REPS_S"
  log "    Repetição $n de $REPETICOES (${DURACAO_S}s)..."

  rodar_k6 "k6-rep$n" "rep$n" "$DURACAO_S"
  coletar_recursos "$PASTA_RESULTADOS/rep$n-recursos.csv" &
  PID_COLETA=$!

  esperar_k6 "k6-rep$n" "$DURACAO_S"
  kill "$PID_COLETA" 2>/dev/null || true
  wait "$PID_COLETA" 2>/dev/null || true
  PID_COLETA=""

  # Separa o resumo JSON do resto do log do k6.
  echo "$LOG_K6" | sed -n '/===RESUMO-INICIO===/,/===RESUMO-FIM===/p' | sed '1d;$d' > "$PASTA_RESULTADOS/rep$n.json"
  [[ -s "$PASTA_RESULTADOS/rep$n.json" ]] || erro "não encontrei o resumo do k6 no log da repetição $n."
  kubectl delete job "k6-rep$n" -n "$VARIANTE" >/dev/null

  p95=$(grep -o '"p95": *[0-9.]*' "$PASTA_RESULTADOS/rep$n.json" | grep -o '[0-9.]*$')
  sucesso=$(grep -o '"taxa_sucesso": *[0-9.]*' "$PASTA_RESULTADOS/rep$n.json" | grep -o '[0-9.]*$')
  amostras=$(( $(wc -l < "$PASTA_RESULTADOS/rep$n-recursos.csv") - 1 ))
  log "    -> p95 = ${p95} ms | sucesso = ${sucesso} | ${amostras} linhas de recursos"
done

echo "fim=$(date '+%Y-%m-%d %H:%M:%S')" >> "$PASTA_RESULTADOS/execucao.txt"

log "4/4 Removendo a variante..."
limpar
trap - EXIT
log "=== Pronto. Resultados em results/$VARIANTE/ ==="
