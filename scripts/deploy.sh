#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Trading Copilot — Deployment Script
# Orchestrates: Terraform outputs -> ECR push -> Lambda update -> S3 deploy -> CF invalidation
# =============================================================================

AWS_REGION="${AWS_REGION:-us-east-1}"

log()   { printf '\033[0;32m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$1"; }
error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }

# ── Step 1: Read Terraform outputs ──────────────────────────────────────────
log "Reading Terraform outputs..."
cd infra
ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null) || error "Failed to get ecr_repository_url"
LAMBDA_FN=$(terraform output -raw trade_executor_lambda 2>/dev/null) || error "Failed to get trade_executor_lambda"
S3_BUCKET=$(terraform output -raw dashboard_bucket_name 2>/dev/null) || error "Failed to get dashboard_bucket_name"
CF_DIST_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null) || error "Failed to get cloudfront_distribution_id"
EC2_IP=$(terraform output -raw ec2_public_ip 2>/dev/null) || warn "Failed to get ec2_public_ip"
cd ..

log "  ECR:        $ECR_URL"
log "  Lambda:     $LAMBDA_FN"
log "  S3 Bucket:  $S3_BUCKET"
log "  CloudFront: $CF_DIST_ID"
log "  EC2:        ${EC2_IP:-N/A}"

# ── Step 2: Build and push Docker image to ECR ─────────────────────────────
log "Building Docker image..."
IMAGE_TAG="$(git rev-parse --short HEAD)-$(date +%s)"
IMAGE_URI="${ECR_URL}:${IMAGE_TAG}"
IMAGE_LATEST="${ECR_URL}:latest"

docker build -t "${IMAGE_LATEST}" -t "${IMAGE_URI}" -f Dockerfile . || error "Docker build failed"

log "Pushing to ECR..."
AWS_ACCOUNT_ID=$(echo "${ECR_URL}" | cut -d. -f1)
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" || \
    error "ECR login failed"

docker push "${IMAGE_URI}" || error "Failed to push ${IMAGE_URI}"
docker push "${IMAGE_LATEST}" || error "Failed to push latest tag"
log "Pushed: ${IMAGE_URI}"

# ── Step 3: Update Lambda function code ─────────────────────────────────────
log "Updating Lambda function: ${LAMBDA_FN}..."
aws lambda update-function-code \
    --function-name "${LAMBDA_FN}" \
    --s3-bucket "$(echo "${ECR_URL}" | cut -d/ -f1 | cut -d. -f1)-lambda-packages" \
    --zip-file fileb://infra/.build/placeholder.zip \
    --region "${AWS_REGION}" \
    --no-cli-pager 2>/dev/null || warn "Lambda update skipped (using placeholder zip — CI will deploy real code)"

# ── Step 4: Deploy dashboard to S3 ─────────────────────────────────────────
if [ -d "apps/dashboard/build" ] || [ -d "apps/dashboard/dist" ]; then
    DASHBOARD_DIR="apps/dashboard/build"
    [ -d "apps/dashboard/dist" ] && DASHBOARD_DIR="apps/dashboard/dist"

    log "Syncing dashboard to S3..."
    aws s3 sync "${DASHBOARD_DIR}" "s3://${S3_BUCKET}/" \
        --region "${AWS_REGION}" \
        --delete \
        --cache-control "public, max-age=3600" || error "S3 sync failed"
    log "Dashboard deployed to s3://${S3_BUCKET}/"
else
    warn "No dashboard build found (apps/dashboard/build or apps/dashboard/dist). Skipping S3 sync."
fi

# ── Step 5: Update EC2 container ───────────────────────────────────────────
if [ -n "${EC2_IP:-}" ]; then
    EC2_INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=${EC2_IP}" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text --region "${AWS_REGION}" 2>/dev/null) || true

    if [ -n "${EC2_INSTANCE_ID}" ] && [ "${EC2_INSTANCE_ID}" != "None" ]; then
        log "Updating container on EC2 (${EC2_INSTANCE_ID})..."
        aws ssm send-command \
            --instance-ids "${EC2_INSTANCE_ID}" \
            --document-name "AWS-RunShellScript" \
            --parameters "commands=[
                'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com',
                'docker pull ${IMAGE_LATEST}',
                'docker stop trading-copilot-api 2>/dev/null || true',
                'docker rm trading-copilot-api 2>/dev/null || true',
                'docker run -d --name trading-copilot-api --restart unless-stopped -p 8000:8000 -e AWS_REGION=${AWS_REGION} -e TABLE_NAME=\$(aws ssm get-parameter --name /${ECR_URL%%/*}/table-name --query Parameter.Value --output text 2>/dev/null || echo trading-copilot-prod) ${IMAGE_LATEST}'
            ]" \
            --region "${AWS_REGION}" \
            --no-cli-pager 2>/dev/null || warn "SSM command failed — EC2 may need SSM agent. SSH manually to deploy."
        log "EC2 container update initiated"
    else
        warn "Could not find EC2 instance ID. Skipping EC2 deploy."
    fi
else
    warn "No EC2 IP available. Skipping EC2 deploy."
fi

# ── Step 6: Invalidate CloudFront cache ─────────────────────────────────────
log "Invalidating CloudFront cache..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "${CF_DIST_ID}" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text \
    --region "${AWS_REGION}") || error "CloudFront invalidation failed"

log "Invalidation started: ${INVALIDATION_ID}"

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  Deployment complete"
echo "  Image:        ${IMAGE_URI}"
echo "  Lambda:       ${LAMBDA_FN}"
echo "  S3:           ${S3_BUCKET}"
echo "  CloudFront:   ${CF_DIST_ID}"
echo "  Invalidation: ${INVALIDATION_ID}"
echo "═══════════════════════════════════════"
