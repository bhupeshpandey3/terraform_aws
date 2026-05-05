terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  db_port      = var.db_engine == "postgres" ? 5432 : 3306
  param_family = var.db_engine == "postgres" ? "postgres${split(".", var.db_engine_version)[0]}" : "mysql${var.db_engine_version}"
  log_exports  = var.db_engine == "postgres" ? ["postgresql", "upgrade"] : ["audit", "error", "general", "slowquery"]
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "RDS - allow inbound from ECS tasks only"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ecs_security_group_id != "" ? [1] : []
    content {
      from_port       = local.db_port
      to_port         = local.db_port
      protocol        = "tcp"
      security_groups = [var.ecs_security_group_id]
      description     = "ECS tasks to DB"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-sg" })
}

# ─── Subnet Group ─────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-subnet-group" })
}

# ─── Parameter Group ──────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  family = local.param_family
  name   = "${var.name_prefix}-db-params"

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-params" })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── RDS Instance ─────────────────────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier     = "${var.name_prefix}-db"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 3
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = local.db_port

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  publicly_accessible = false
  multi_az            = var.multi_az

  backup_retention_period    = var.backup_retention_period
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.name_prefix}-db-final-snapshot" : null

  enabled_cloudwatch_logs_exports = local.log_exports

  tags = merge(var.tags, { Name = "${var.name_prefix}-db" })
}
