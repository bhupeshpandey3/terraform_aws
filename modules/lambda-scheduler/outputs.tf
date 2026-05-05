output "lambda_arn" {
  description = "Scheduler Lambda ARN"
  value       = aws_lambda_function.scheduler.arn
}

output "lambda_function_name" {
  description = "Scheduler Lambda function name"
  value       = aws_lambda_function.scheduler.function_name
}

output "stop_rule_arn" {
  description = "EventBridge stop rule ARN"
  value       = aws_cloudwatch_event_rule.stop.arn
}

output "start_rule_arn" {
  description = "EventBridge start rule ARN"
  value       = aws_cloudwatch_event_rule.start.arn
}
