# Trading Copilot

Personal AI-powered trading command center.

## Quick Start

```bash
# 1. Bootstrap Terraform state backend (once)
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh

# 2. Configure variables
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Deploy infrastructure
cd infra
terraform init
terraform plan
terraform apply
```

## Per-Environment Table Name via `.env`

If you only want environment-specific control for the DynamoDB table name:

```bash
cd infra

# one-time setup
cp .env.development.example .env.development
cp .env.production.example .env.production

# development
set -a && source .env.development && set +a
terraform plan

# production
set -a && source .env.production && set +a
terraform plan
```

`TF_VAR_dynamodb_table_name` maps to Terraform variable `dynamodb_table_name`.
If unset, Terraform falls back to `${project_name}-${environment}`.

## Project Structure

```
trading-copilot/
├── .github/workflows/    # CI/CD pipeline
├── infra/                # Terraform (all AWS resources)
├── apps/
│   ├── api/              # FastAPI heartbeat engine (Python)
│   ├── dashboard/        # React trading dashboard (TypeScript)
│   └── lambdas/          # Trade executor + WebSocket push
└── scripts/              # Bootstrap, playbook upload CLI
```

## CI/CD Pipeline

### GitHub Actions Workflows

- **CI** (`.github/workflows/ci.yml`) — Runs on every push/PR: Python syntax checks, Terraform fmt/validate
- **Deploy** (`.github/workflows/deploy.yml`) — Runs on push to `main`: Terraform plan/apply, Docker build + ECR push, S3 deploy, CloudFront invalidation

### Required GitHub Secrets

Configure in Settings > Secrets and variables > Actions:

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub OIDC authentication |
| `ALPACA_API_KEY` | Alpaca Markets API key |
| `ALPACA_SECRET_KEY` | Alpaca Markets secret key |
| `EC2_KEY_PAIR` | EC2 key pair name for SSH access |
| `ALLOWED_SSH_CIDR` | CIDR block for SSH access (e.g., `1.2.3.4/32`) |

### OIDC Setup

Create an IAM role with this trust policy (replace `ACCOUNT_ID` and `OWNER/REPO`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:*"
      }
    }
  }]
}
```

The role needs permissions for: EC2, Lambda, API Gateway, DynamoDB, S3, CloudFront, CloudWatch, ECR, IAM, Logs.

### Monitoring

- **CloudWatch Dashboard**: Auto-created via Terraform — Lambda metrics, API Gateway errors, DynamoDB capacity
- **Alarms**: Lambda errors, API Gateway 4xx/5xx, DynamoDB throttling
- **Access Logs**: API Gateway WebSocket logs in CloudWatch

## Monthly Cost: ~$1.50 (year 1)
