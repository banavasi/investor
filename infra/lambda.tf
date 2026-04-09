# =============================================================================
# Lambda — Trade Executor + WebSocket Push
# =============================================================================

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_exec" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatch"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:DescribeStream", "dynamodb:ListStreams"]
        Resource = [aws_dynamodb_table.trading.arn, "${aws_dynamodb_table.trading.arn}/index/*", "${aws_dynamodb_table.trading.arn}/stream/*"]
      },
      {
        Sid      = "SSM"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
      },
      {
        Sid      = "WebSocketPost"
        Effect   = "Allow"
        Action   = "execute-api:ManageConnections"
        Resource = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.websocket.id}/*"
      }
    ]
  })
}

# Placeholder zip — CI/CD replaces with real code
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/.build/placeholder.zip"

  source {
    content  = "def handler(event, context):\n    return {\"statusCode\": 200, \"body\": \"placeholder\"}\n"
    filename = "handler.py"
  }
}

# --- Trade Executor ---
resource "aws_lambda_function" "trade_executor" {
  function_name = "${var.project_name}-trade-executor"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      TABLE_NAME        = aws_dynamodb_table.trading.name
      ENVIRONMENT       = var.environment
      SSM_PREFIX        = "/${var.project_name}"
      ALPACA_PAPER_MODE = "true"
    }
  }

  tags = { Name = "${var.project_name}-trade-executor" }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# --- WebSocket Push (DynamoDB Streams trigger) ---
resource "aws_lambda_function" "ws_push" {
  function_name = "${var.project_name}-ws-push"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      WEBSOCKET_API_ENDPOINT = "https://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
      TABLE_NAME             = aws_dynamodb_table.trading.name
    }
  }

  tags = { Name = "${var.project_name}-ws-push" }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# Stream trigger: only fire on new/updated alerts
resource "aws_lambda_event_source_mapping" "dynamodb_to_ws" {
  event_source_arn  = aws_dynamodb_table.trading.stream_arn
  function_name     = aws_lambda_function.ws_push.arn
  starting_position = "LATEST"
  batch_size        = 10

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
      })
    }
  }
}
