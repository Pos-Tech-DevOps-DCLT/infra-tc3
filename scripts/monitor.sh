#Roda em loop a cada 15 segundos (configurável) mostrando HPA, pods, CPU/memória, estado do KEDA,
#mensagens na fila SQS e total de itens no DynamoDB.
#Tudo vai sendo gravado em um arquivo chamado monitor-YYYYMMDD-HHMMSS.log

#!/usr/bin/env bash
# monitor.sh — Monitoramento contínuo durante os testes de carga
#
# Roda em terminal separado enquanto o load-test.sh executa.
# Gera um arquivo de log como evidência.
#
# Uso:
#   ./scripts/monitor.sh [INTERVALO_SEGUNDOS]
#   Exemplo: ./scripts/monitor.sh 15
#
# Pressione Ctrl+C para encerrar.
INTERVAL="${1:-15}"
LOGFILE="monitor-$(date +%Y%m%d-%H%M%S).log"

echo "Monitor iniciado — log: ${LOGFILE}" | tee "$LOGFILE"
echo "Intervalo: ${INTERVAL}s — Ctrl+C para encerrar" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

while true; do
  {
    echo "────────────────────────────────────────"
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    echo "[ HPA ]"
    kubectl get hpa -n evaluation-service 2>/dev/null
    kubectl get hpa -n analytics-service  2>/dev/null

    echo ""
    echo "[ Pods ]"
    kubectl get pods -n evaluation-service 2>/dev/null
    kubectl get pods -n analytics-service  2>/dev/null

    echo ""
    echo "[ CPU / Memória ]"
    kubectl top pods -n evaluation-service 2>/dev/null || echo "  (Metrics Server indisponível)"
    kubectl top pods -n analytics-service  2>/dev/null || echo "  (Metrics Server indisponível)"

    echo ""
    echo "[ KEDA ScaledObjects ]"
    kubectl get scaledobject -n evaluation-service 2>/dev/null || true
    kubectl get scaledobject -n analytics-service  2>/dev/null || true

    echo ""
    echo "[ SQS — mensagens na fila ]"
    SQS_URL=$(kubectl get configmap evaluation-service-config \
      -n evaluation-service \
      -o jsonpath='{.data.AWS_SQS_URL}' 2>/dev/null || true)

    if [[ -n "$SQS_URL" && "$SQS_URL" != *"<AWS_ACCOUNT_ID>"* ]]; then
      aws sqs get-queue-attributes \
        --queue-url "$SQS_URL" \
        --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
        --query 'Attributes' \
        --output table 2>/dev/null || echo "  (sem acesso à fila)"
    else
      echo "  (URL SQS ainda com placeholder — substitua no ConfigMap)"
    fi

    echo ""
    echo "[ DynamoDB — total de itens ]"
    aws dynamodb describe-table \
      --table-name tech-challenge-prod-analytics-events \
      --query 'Table.ItemCount' \
      --output text 2>/dev/null \
      | xargs -I{} echo "  ItemCount: {}" \
      || echo "  (sem acesso ao DynamoDB)"

  } | tee -a "$LOGFILE"

  sleep "$INTERVAL"
done