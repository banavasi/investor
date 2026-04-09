output "dynamodb_table_name" {
  description = "DynamoDB single table name"
  value       = aws_dynamodb_table.trading.name
}

output "ec2_public_ip" {
  description = "Public IP of the heartbeat EC2 instance"
  value       = aws_instance.heartbeat.public_ip
}

output "ecr_repository_url" {
  description = "ECR repo URL for the API Docker image"
  value       = aws_ecr_repository.api.repository_url
}

output "dashboard_bucket_name" {
  description = "S3 bucket name for the React dashboard"
  value       = aws_s3_bucket.dashboard.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation"
  value       = aws_cloudfront_distribution.dashboard.id
}

output "cloudfront_domain" {
  description = "CloudFront domain name for the dashboard"
  value       = aws_cloudfront_distribution.dashboard.domain_name
}

output "websocket_api_endpoint" {
  description = "API Gateway WebSocket endpoint URL"
  value       = aws_apigatewayv2_stage.ws_prod.invoke_url
}

output "trade_executor_lambda" {
  description = "Trade executor Lambda function name"
  value       = aws_lambda_function.trade_executor.function_name
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group name for Lambda functions"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_apigateway" {
  description = "CloudWatch log group name for API Gateway"
  value       = aws_cloudwatch_log_group.apigateway_logs.name
}

output "cloudwatch_log_group_ec2" {
  description = "CloudWatch log group name for EC2 instances"
  value       = aws_cloudwatch_log_group.ec2_logs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard in the AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.trading_copilot.dashboard_name}"
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC — set as AWS_ROLE_ARN secret"
  value       = aws_iam_role.github_actions.arn
}
