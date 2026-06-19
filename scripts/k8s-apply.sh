#!/usr/bin/env bash
# Apply all Kubernetes manifests in dependency order.
# Run from the project root after `terraform apply` has completed.
# Prerequisites: kubectl configured to point at the EKS cluster.
#
# Usage:
#   ./scripts/k8s-apply.sh
#
# Before running, replace placeholder values in k8s/ manifests:
#   <ECR_URL>              -> terraform output -json ecr_repository_urls | jq -r '.["<service>"]'
#   <IRSA_ROLE_ARN>        -> terraform output irsa_evaluation_service_role_arn  (evaluation-service)
#                         -> terraform output irsa_analytics_service_role_arn   (analytics-service)
#   <BASE64_*>             -> echo -n "<value>" | base64
#   <SQS_QUEUE_URL>        -> terraform output -json connection_strings | jq -r '.sqs_queue_url'
#   <DYNAMODB_TABLE_NAME>  -> terraform output -json connection_strings | jq -r '.dynamodb_table_name'

set -euo pipefail

K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)/k8s"

echo "==> Applying namespaces..."
kubectl apply -f "$K8S_DIR/namespaces.yaml"

echo "==> Applying auth-service..."
kubectl apply -f "$K8S_DIR/auth-service/"

echo "==> Applying flag-service..."
kubectl apply -f "$K8S_DIR/flag-service/"

echo "==> Applying targeting-service..."
kubectl apply -f "$K8S_DIR/targeting-service/"

echo "==> Applying evaluation-service..."
kubectl apply -f "$K8S_DIR/evaluation-service/"

echo "==> Applying analytics-service..."
kubectl apply -f "$K8S_DIR/analytics-service/"

echo "==> Applying Ingress rules..."
kubectl apply -f "$K8S_DIR/ingress.yaml"

echo ""
echo "==> Waiting for deployments to be ready..."
for ns in auth-service flag-service targeting-service evaluation-service analytics-service; do
  kubectl rollout status deployment/"$ns" -n "$ns" --timeout=120s || true
done

echo ""
echo "==> Ingress external IP / hostname:"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}' 2>/dev/null || \
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}' 2>/dev/null || \
echo "  (LoadBalancer still provisioning — retry in a minute)"

echo ""
echo "Done."
