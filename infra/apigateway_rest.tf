# =============================================================================
# API Gateway — HTTP API v2 with Cognito JWT authorizer
# =============================================================================

resource "aws_apigatewayv2_api" "rest" {
  name          = "${var.project_name}-rest-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [
      "https://*.cloudfront.net",
      "http://localhost:3000",
    ]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3600
  }

  tags = { Name = "${var.project_name}-rest-api" }
}

# --- Cognito JWT Authorizer ---
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.rest.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    audience = [aws_cognito_user_pool_client.dashboard.id]
  }
}

# --- Lambda Integrations ---
resource "aws_apigatewayv2_integration" "crud" {
  api_id                 = aws_apigatewayv2_api.rest.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.crud.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "trade" {
  api_id                 = aws_apigatewayv2_api.rest.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.trade.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "compute_proxy" {
  api_id                 = aws_apigatewayv2_api.rest.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.compute_proxy.invoke_arn
  payload_format_version = "2.0"
}

# --- Routes ---

# Health check — no auth
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.rest.id
  route_key = "GET /api/health"
  target    = "integrations/${aws_apigatewayv2_integration.crud.id}"
}

# CRUD routes — auth required
resource "aws_apigatewayv2_route" "heartbeats_today" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/heartbeats/today"
  target             = "integrations/${aws_apigatewayv2_integration.crud.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "alerts_pending" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/alerts/pending"
  target             = "integrations/${aws_apigatewayv2_integration.crud.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "positions_tracked" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/positions/tracked"
  target             = "integrations/${aws_apigatewayv2_integration.crud.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "trades" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/trades"
  target             = "integrations/${aws_apigatewayv2_integration.crud.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "trades_by_symbol" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/trades/{symbol}"
  target             = "integrations/${aws_apigatewayv2_integration.crud.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Trade routes — auth required
resource "aws_apigatewayv2_route" "account" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/account"
  target             = "integrations/${aws_apigatewayv2_integration.trade.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "positions" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "GET /api/positions"
  target             = "integrations/${aws_apigatewayv2_integration.trade.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "trade" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "POST /api/trade"
  target             = "integrations/${aws_apigatewayv2_integration.trade.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Compute routes — auth required
resource "aws_apigatewayv2_route" "heartbeat" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "POST /api/heartbeat"
  target             = "integrations/${aws_apigatewayv2_integration.compute_proxy.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "heartbeat_indicators" {
  api_id             = aws_apigatewayv2_api.rest.id
  route_key          = "POST /api/heartbeat/indicators-only"
  target             = "integrations/${aws_apigatewayv2_integration.compute_proxy.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- Stage ---
resource "aws_apigatewayv2_stage" "rest_prod" {
  api_id      = aws_apigatewayv2_api.rest.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigateway_logs.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      method    = "$context.httpMethod"
      path      = "$context.path"
      status    = "$context.status"
      latency   = "$context.integrationLatency"
      error     = "$context.error.message"
    })
  }
}

# --- Lambda Permissions ---
resource "aws_lambda_permission" "apigw_crud" {
  statement_id  = "AllowAPIGatewayInvokeCRUD"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rest.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_trade" {
  statement_id  = "AllowAPIGatewayInvokeTrade"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trade.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rest.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_compute_proxy" {
  statement_id  = "AllowAPIGatewayInvokeComputeProxy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compute_proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rest.execution_arn}/*/*"
}
