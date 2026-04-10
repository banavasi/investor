variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "trading-copilot"
}

variable "dynamodb_table_name" {
  description = "Explicit DynamoDB table name override (optional)"
  type        = string
  default     = ""
}

variable "ec2_instance_type" {
  description = "EC2 instance type for heartbeat engine"
  type        = string
  default     = "t3.micro"
}

variable "ec2_key_pair_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 (your IP)"
  type        = string
}

variable "alpaca_api_key" {
  description = "Alpaca API key"
  type        = string
  sensitive   = true
}

variable "alpaca_secret_key" {
  description = "Alpaca secret key"
  type        = string
  sensitive   = true
}

variable "telegram_bot_token" {
  description = "Telegram bot token for alerts"
  type        = string
  sensitive   = true
  default     = ""
}

variable "telegram_chat_id" {
  description = "Telegram chat ID for alerts"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Custom domain for the dashboard (optional)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude (from Max subscription)"
  type        = string
  sensitive   = true
  default     = ""
}
