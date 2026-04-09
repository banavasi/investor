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
