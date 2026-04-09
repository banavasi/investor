#!/bin/bash
# =============================================================================
# Bootstrap — Create Terraform State Backend (run once)
# Usage: ./scripts/bootstrap.sh [region]
# =============================================================================
set -euo pipefail

REGION="${1:-us-east-1}"
BUCKET="trading-copilot-tf-state"
TABLE="trading-copilot-tf-locks"

echo "==> Creating state bucket: ${BUCKET}"
if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "    Already exists, skipping."
else
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  aws s3api put-bucket-versioning --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "${BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'
  aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true, "IgnorePublicAcls": true,
      "BlockPublicPolicy": true, "RestrictPublicBuckets": true
    }'
  echo "    Created."
fi

echo "==> Creating lock table: ${TABLE}"
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" 2>/dev/null; then
  echo "    Already exists, skipping."
else
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  echo "    Created."
fi

echo ""
echo "==> Done. Now run: cd infra && terraform init"
