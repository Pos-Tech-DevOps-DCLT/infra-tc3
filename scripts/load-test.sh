#Vamos rodar 4 cenários progressivos. Começando com carga leve, subindo para carga que dispara o HPA,
#testa o analytics-service separado e termina com 60 segundos de carga sustentada em ambos ao mesmo tempo.
#Deoius de cada fase ele mostrará o estado dos HPAs e dos pods.

#!/usr/bin/env bash
# load-test.sh — Testes de carga para evidenciar o autoscaling (Parte 4)
#
# Pré-requisitos:
#   hey:  go install github.com/rakyll/hey@latest   (ou: brew install hey)
#   ab:   sudo apt-get install apache2-utils
#
# Uso:
#   ./scripts/load-test.sh <HOSTNAME_DO_INGRESS>
#
# Obtenha o hostname com:
#   kubectl get svc -n ingress-nginx ingress-nginx-controller \
#     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
set -euo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "Uso: $0 <HOSTNAME_DO_INGRESS>"
  exit 1
fi
BASE_URL="${BASE_URL%/}"

echo "=================================================="
echo " ToggleMaster — Testes de Carga (Parte 4)"
echo " Target: http://${BASE_URL}"
echo "=================================================="

# ── Funções auxiliares ──────────────────────────────────────────────────────

watch_pods() {
  echo ""
  echo ">>> Pods em $1:"
  kubectl get pods -n "$1"
}

watch_hpa() {
  echo ""
  echo ">>> HPA:"
  kubectl get hpa -n evaluation-service
  kubectl get hpa -n analytics-service
}

# ── Aquecimento ─────────────────────────────────────────────────────────────

echo ""
echo "==> Verificando health checks antes de começar..."
curl -sf "http://${BASE_URL}/evaluate/health" && echo "  evaluation-service OK" || echo "  evaluation-service ERRO"
curl -sf "http://${BASE_URL}/analytics/health" && echo "  analytics-service OK"  || echo "  analytics-service ERRO"

# ── Teste 1: carga moderada no evaluation-service ───────────────────────────

echo ""
echo "==> [1/4] hey — 200 requisições, 20 concorrentes (evaluation-service)"
watch_pods evaluation-service

hey -n 200 -c 20 "http://${BASE_URL}/evaluate/health"

watch_hpa
sleep 10

# ── Teste 2: carga alta — deve disparar HPA ─────────────────────────────────

echo ""
echo "==> [2/4] hey — 1000 requisições, 50 concorrentes (deve escalar)"
watch_pods evaluation-service

hey -n 1000 -c 50 "http://${BASE_URL}/evaluate/health"

echo ">>> Aguardando 30s para o HPA reagir..."
sleep 30
watch_hpa
watch_pods evaluation-service

# ── Teste 3: ab no analytics-service ────────────────────────────────────────

echo ""
echo "==> [3/4] ab — 500 requisições, 30 concorrentes (analytics-service)"
watch_pods analytics-service

ab -n 500 -c 30 "http://${BASE_URL}/analytics/health"

echo ">>> Aguardando 30s para o HPA reagir..."
sleep 30
watch_hpa
watch_pods analytics-service

# ── Teste 4: carga sustentada por 60s em ambos ──────────────────────────────

echo ""
echo "==> [4/4] hey — 60s sustentado, 40 concorrentes em cada serviço"

hey -z 60s -c 40 "http://${BASE_URL}/evaluate/health" &
PID1=$!
hey -z 60s -c 40 "http://${BASE_URL}/analytics/health" &
PID2=$!

for i in 1 2 3 4; do
  sleep 15
  echo "--- ${i}x15s ---"
  watch_hpa
done

wait $PID1; wait $PID2

# ── Resumo ───────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo " Resumo final"
echo "=================================================="

kubectl get hpa -n evaluation-service -o wide
kubectl get hpa -n analytics-service  -o wide
echo ""
kubectl get pods -n evaluation-service
kubectl get pods -n analytics-service
echo ""
kubectl top pods -n evaluation-service 2>/dev/null || true
kubectl top pods -n analytics-service  2>/dev/null || true

echo ""
echo "==> Salve este output como evidência de escalabilidade."
