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

## Monthly Cost: ~$1.50 (year 1)
