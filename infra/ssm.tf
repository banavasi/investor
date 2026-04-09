# =============================================================================
# SSM Parameter Store — Secrets
# =============================================================================

resource "aws_ssm_parameter" "alpaca_api_key" {
  name  = "/${var.project_name}/alpaca/api_key"
  type  = "SecureString"
  value = var.alpaca_api_key
  tags  = { Name = "${var.project_name}-alpaca-api-key" }
}

resource "aws_ssm_parameter" "alpaca_secret_key" {
  name  = "/${var.project_name}/alpaca/secret_key"
  type  = "SecureString"
  value = var.alpaca_secret_key
  tags  = { Name = "${var.project_name}-alpaca-secret-key" }
}

resource "aws_ssm_parameter" "telegram_bot_token" {
  count = var.telegram_bot_token != "" ? 1 : 0
  name  = "/${var.project_name}/telegram/bot_token"
  type  = "SecureString"
  value = var.telegram_bot_token
  tags  = { Name = "${var.project_name}-telegram-bot-token" }
}

resource "aws_ssm_parameter" "telegram_chat_id" {
  count = var.telegram_chat_id != "" ? 1 : 0
  name  = "/${var.project_name}/telegram/chat_id"
  type  = "String"
  value = var.telegram_chat_id
  tags  = { Name = "${var.project_name}-telegram-chat-id" }
}
