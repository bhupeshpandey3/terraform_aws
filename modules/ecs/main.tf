terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  is_fargate  = var.launch_type == "FARGATE"
  has_alb     = var.alb_target_group_arn != ""
  has_s3      = var.s3_bucket_arn != ""
}

# ─── Cluster ──────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = local.is_fargate ? ["FARGATE", "FARGATE_SPOT"] : []

  dynamic "default_capacity_provider_strategy" {
    for_each = local.is_fargate ? [1] : []
    content {
      capacity_provider = "FARGATE"
      weight            = 1
    }
  }
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "ecs" {
  name        = "${var.name_prefix}-ecs-sg"
  description = "ECS tasks - allow inbound from ALB only"
  vpc_id      = var.vpc_id

  # Only add ALB ingress rule when ALB is enabled
  dynamic "ingress" {
    for_each = local.has_alb ? [1] : []
    content {
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
      description     = "ALB to container"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-sg" })
}

# ─── CloudWatch Logs ──────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = 30
  tags              = var.tags
}

# ─── IAM ─────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name_prefix}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # S3 access — only added when S3 bucket is enabled
      local.has_s3 ? [{
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      }] : [],
      [{
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      }]
    )
  })
}

# ─── Task Definition ──────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = [var.launch_type]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "${var.name_prefix}-container"
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = concat(
      [
        { name = "DB_ENDPOINT",  value = var.db_endpoint },
        { name = "ENVIRONMENT",  value = split("-", var.name_prefix)[1] }
      ],
      var.container_environment
    )

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    readonlyRootFilesystem = false
    privileged             = false
  }])

  tags = merge(var.tags, { Name = "${var.name_prefix}-task" })
}

# ─── Service ──────────────────────────────────────────────────────────────────

resource "aws_ecs_service" "main" {
  name                              = "${var.name_prefix}-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.main.arn
  desired_count                     = var.desired_count
  launch_type                       = local.is_fargate ? var.launch_type : null
  scheduling_strategy               = "REPLICA"
  health_check_grace_period_seconds = local.has_alb ? 60 : 0
  force_new_deployment              = true

  dynamic "capacity_provider_strategy" {
    for_each = local.is_fargate ? [] : [1]
    content {
      capacity_provider = "${var.name_prefix}-capacity-provider"
      weight            = 1
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.assign_public_ip
  }

  # Only attach load balancer when ALB is enabled
  dynamic "load_balancer" {
    for_each = local.has_alb ? [1] : []
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = "${var.name_prefix}-container"
      container_port   = var.container_port
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # Scheduler manages desired_count externally
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-service" })

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution]
}
