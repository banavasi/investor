# =============================================================================
# API Gateway — WebSocket for real-time dashboard push
# =============================================================================

resource "aws_apigatewayv2_api" "websocket" {
  name                       = "${var.project_name}-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  tags = { Name = "${var.project_name}-websocket-api" }
}

# $connect
resource "aws_apigatewayv2_integration" "ws_connect" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_push.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "ws_connect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_connect.id}"
}

# $disconnect
resource "aws_apigatewayv2_integration" "ws_disconnect" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_push.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "ws_disconnect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_disconnect.id}"
}

# $default
resource "aws_apigatewayv2_integration" "ws_default" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_push.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "ws_default" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.ws_default.id}"
}

# Stage
resource "aws_apigatewayv2_stage" "ws_prod" {
  api_id      = aws_apigatewayv2_api.websocket.id
  name        = var.environment
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
  }

  tags = { Name = "${var.project_name}-ws-${var.environment}" }
}

# Permission for API GW to invoke Lambda
resource "aws_lambda_permission" "apigw_ws" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_push.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket.execution_arn}/*/*"
}
