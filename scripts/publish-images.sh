#!/usr/bin/env bash
set -euo pipefail

# Publish Docker images to ECR
# Usage: ./scripts/publish-images.sh <aws-region> <aws-account-id> [image-tag]

AWS_REGION="${1:?Usage: $0 <aws-region> <aws-account-id> [image-tag]}"
AWS_ACCOUNT_ID="${2:?Usage: $0 <aws-region> <aws-account-id> [image-tag]}"
IMAGE_TAG="${3:-latest}"
PROJECT_NAME="${PROJECT_NAME:-tech-challenge}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
NAME_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

SERVICES=(
  "auth-service"
  "flag-service"
  "targeting-service"
  "evaluation-service"
  "analytics-service"
)

echo "Authenticating with ECR registry ${REGISTRY}..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

for SERVICE in "${SERVICES[@]}"; do
  REPO="${REGISTRY}/${NAME_PREFIX}/${SERVICE}"
  LOCAL_IMAGE="${SERVICE}:${IMAGE_TAG}"
  REMOTE_IMAGE="${REPO}:${IMAGE_TAG}"

  if ! docker image inspect "${LOCAL_IMAGE}" &>/dev/null; then
    echo "  [SKIP] Local image '${LOCAL_IMAGE}' not found, skipping ${SERVICE}"
    continue
  fi

  echo "  [PUSH] ${LOCAL_IMAGE} -> ${REMOTE_IMAGE}"
  docker tag "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"
  docker push "${REMOTE_IMAGE}"
done

echo "Done."
