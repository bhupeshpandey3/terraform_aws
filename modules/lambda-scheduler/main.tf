terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ─── IAM ─────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "scheduler" {
  name = "${var.name_prefix}-ecs-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.name_prefix}-ecs-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-ecs-scheduler:*"
      }
    ]
  })
}

# ─── Lambda ───────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/aws/lambda/${var.name_prefix}-ecs-scheduler"
  retention_in_days = 14
  tags              = var.tags
}

data "archive_file" "scheduler" {
  type        = "zip"
  source_file = "${path.module}/src/scheduler.py"
  output_path = "${path.module}/scheduler.zip"
}

resource "aws_lambda_function" "scheduler" {
  filename         = data.archive_file.scheduler.output_path
  function_name    = "${var.name_prefix}-ecs-scheduler"
  role             = aws_iam_role.scheduler.arn
  handler          = "scheduler.handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.scheduler.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ECS_CLUSTER_NAME = var.ecs_cluster_name
      ECS_SERVICE_NAME = var.ecs_service_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.scheduler]

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-scheduler" })
}

# ─── EventBridge Rules ────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "stop" {
  name                = "${var.name_prefix}-ecs-stop"
  description         = "Scale ECS service to 0 (stop)"
  schedule_expression = var.schedule_stop_cron
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "stop" {
  rule      = aws_cloudwatch_event_rule.stop.name
  target_id = "StopECS"
  arn       = aws_lambda_function.scheduler.arn
  input     = jsonencode({ desired_count = 0 })
}

resource "aws_lambda_permission" "stop" {
  statement_id  = "AllowEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop.arn
}

resource "aws_cloudwatch_event_rule" "start" {
  name                = "${var.name_prefix}-ecs-start"
  description         = "Scale ECS service to desired count (start)"
  schedule_expression = var.schedule_start_cron
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "start" {
  rule      = aws_cloudwatch_event_rule.start.name
  target_id = "StartECS"
  arn       = aws_lambda_function.scheduler.arn
  input     = jsonencode({ desired_count = var.schedule_desired_count })
}

resource "aws_lambda_permission" "start" {
  statement_id  = "AllowEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start.arn
}
