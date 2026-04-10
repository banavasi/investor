# =============================================================================
# EC2 — Heartbeat Engine
# =============================================================================

# CloudFront IP ranges — used to restrict API port to CloudFront only
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "heartbeat" {
  name        = "${var.project_name}-heartbeat-sg"
  description = "Heartbeat EC2 - SSH restricted, all outbound"

  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description     = "API from CloudFront only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-heartbeat-sg" }
}

# IAM role: DynamoDB + Bedrock + SSM + ECR + Lambda invoke + CloudWatch
resource "aws_iam_role" "heartbeat" {
  name = "${var.project_name}-heartbeat-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "heartbeat" {
  name = "${var.project_name}-heartbeat-policy"
  role = aws_iam_role.heartbeat.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchWriteItem", "dynamodb:BatchGetItem"]
        Resource = [aws_dynamodb_table.trading.arn, "${aws_dynamodb_table.trading.arn}/index/*"]
      },
      {
        Sid      = "Bedrock"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Sid      = "SSM"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
      },
      {
        Sid      = "ECR"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = "*"
      },
      {
        Sid      = "LambdaInvoke"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.trade_executor.arn
      },
      {
        Sid      = "CloudWatch"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "heartbeat" {
  name = "${var.project_name}-heartbeat-profile"
  role = aws_iam_role.heartbeat.name
}

resource "aws_instance" "heartbeat" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_pair_name
  vpc_security_group_ids = [aws_security_group.heartbeat.id]
  iam_instance_profile   = aws_iam_instance_profile.heartbeat.name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Pull and run API container from ECR
    REGION="${var.aws_region}"
    ACCOUNT_ID="${data.aws_caller_identity.current.account_id}"
    ECR_URL="${aws_ecr_repository.api.repository_url}"
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
    docker pull $ECR_URL:latest || true
    docker run -d --name trading-copilot-api --restart unless-stopped \
      -p 8000:8000 \
      -e TABLE_NAME="${aws_dynamodb_table.trading.name}" \
      -e AWS_REGION="$REGION" \
      -e ENVIRONMENT="${var.environment}" \
      $ECR_URL:latest || true

    echo "bootstrap complete" > /home/ec2-user/bootstrap.log
  EOF

  tags = { Name = "${var.project_name}-heartbeat" }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
