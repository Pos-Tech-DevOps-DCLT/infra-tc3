#!/usr/bin/env bash
# Install Metrics Server, Nginx Ingress Controller, and KEDA into the EKS cluster.
# Run this AFTER terraform apply has finished and kubectl is configured.
#
# Usage:
#   cd terraform
#   KEDA_ROLE_ARN=$(terraform output -raw irsa_keda_role_arn)
#   cd ..
#   ./scripts/helm-install.sh "$KEDA_ROLE_ARN"

set -euo pipefail

KEDA_ROLE_ARN="${1:-}"

if [[ -z "$KEDA_ROLE_ARN" ]]; then
  echo "Usage: $0 <keda-irsa-role-arn>"
  echo ""
  echo "Get the ARN with:"
  echo "  cd terraform && terraform output -raw irsa_keda_role_arn"
  exit 1
fi

# Verify kubectl is pointed at the right cluster
echo "==> Current cluster:"
kubectl config current-context
echo ""

# ── Add Helm repositories ──────────────────────────────────────────────────
echo "==> Adding Helm repositories..."
helm repo add metrics-server  https://kubernetes-sigs.github.io/metrics-server/
helm repo add ingress-nginx   https://kubernetes.github.io/ingress-nginx
helm repo add kedacore         https://kedacore.github.io/charts
helm repo update

# ── Metrics Server ─────────────────────────────────────────────────────────
echo ""
echo "==> Installing Metrics Server..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --version "~3.12" \
  --set args[0]="--kubelet-insecure-tls" \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=64Mi \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=128Mi \
  --wait --timeout 3m

# ── Nginx Ingress Controller ───────────────────────────────────────────────
echo ""
echo "==> Installing Nginx Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version "~4.10" \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.service.type=LoadBalancer \
  --set "controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type=nlb" \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=64Mi \
  --set controller.resources.limits.cpu=300m \
  --set controller.resources.limits.memory=192Mi \
  --wait --timeout 5m

# ── KEDA ───────────────────────────────────────────────────────────────────
echo ""
echo "==> Installing KEDA..."
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace \
  --version "~2.14" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KEDA_ROLE_ARN}" \
  --set resources.operator.requests.cpu=50m \
  --set resources.operator.requests.memory=64Mi \
  --set resources.operator.limits.cpu=300m \
  --set resources.operator.limits.memory=192Mi \
  --set resources.metricServer.requests.cpu=50m \
  --set resources.metricServer.requests.memory=64Mi \
  --set resources.metricServer.limits.cpu=200m \
  --set resources.metricServer.limits.memory=128Mi \
  --wait --timeout 5m

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "==> All charts installed. Verifying..."
echo ""
kubectl get pods -n kube-system      -l app.kubernetes.io/name=metrics-server
kubectl get pods -n ingress-nginx    -l app.kubernetes.io/name=ingress-nginx
kubectl get pods -n keda
echo ""
echo "==> Ingress external hostname (may take 2-3 minutes to appear):"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}' 2>/dev/null || \
  echo "  (still provisioning — run the command above again in a minute)"
