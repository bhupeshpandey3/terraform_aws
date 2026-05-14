variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "environment must be dev, staging, prod, or test."
  }
}

variable "project_name" {
  description = "Project name used in all resource naming"
  type        = string
}

# ─── VPC ─────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks (one per AZ)"
  type        = list(string)
}

variable "enable_s3" {
  description = "Enable S3 bucket for application assets"
  type        = bool
}

variable "enable_alb" {
  description = "Enable Application Load Balancer"
  type        = bool
}

variable "enable_rds" {
  description = "Enable RDS database instance"
  type        = bool
}

variable "enable_ecs" {
  description = "Enable ECS cluster and service"
  type        = bool
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateways for private subnet internet access. Set false in dev to save ~$65/month; VPC endpoints replace it for AWS services."
  type        = bool
}

variable "enable_ecr" {
  description = "Enable ECR repositories for Docker images"
  type        = bool
}

variable "ecr_repositories" {
  description = "List of service names to create ECR repos for (e.g. [\"backend\", \"frontend\"])"
  type        = list(string)
  default     = ["app"]
}

# ─── ECS ─────────────────────────────────────────────────────────────────────

variable "ecs_launch_type" {
  description = "ECS launch type: FARGATE or EC2"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.ecs_launch_type)
    error_message = "ecs_launch_type must be FARGATE or EC2."
  }
}

variable "ecs_desired_count" {
  description = "Desired ECS task count"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Container image URI"
  type        = string
}

variable "container_environment" {
  description = "Extra environment variables injected into the ECS container (list of {name, value} objects)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 80
}

variable "container_cpu" {
  description = "Container CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Container memory in MiB"
  type        = number
  default     = 512
}

# ─── EC2 (ECS EC2 launch type) ───────────────────────────────────────────────

variable "ec2_instance_type" {
  description = "EC2 instance type for ECS container instances"
  type        = string
  default     = "t3.medium"
}

variable "ec2_desired_capacity" {
  description = "ASG desired capacity for ECS EC2 instances"
  type        = number
  default     = 2
}

variable "ec2_min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 1
}

variable "ec2_max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 4
}

# ─── RDS ─────────────────────────────────────────────────────────────────────

variable "db_engine" {
  description = "Database engine (mysql or postgres)"
  type        = string
  default     = "mysql"
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 7
}

# ─── S3 ──────────────────────────────────────────────────────────────────────

variable "s3_bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

# ─── ALB ─────────────────────────────────────────────────────────────────────

variable "alb_internal" {
  description = "Make ALB internal (private)"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "ALB target group health check path"
  type        = string
  default     = "/health"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (leave empty for HTTP only)"
  type        = string
  default     = ""
}

# ─── Scheduler ───────────────────────────────────────────────────────────────

variable "enable_scheduler" {
  description = "Enable EventBridge-based ECS start/stop scheduler"
  type        = bool
}

variable "schedule_stop_cron" {
  description = "EventBridge cron expression to stop ECS service (UTC)"
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "schedule_start_cron" {
  description = "EventBridge cron expression to start ECS service (UTC)"
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "schedule_desired_count" {
  description = "Task count to set when scheduler starts the service"
  type        = number
  default     = 2
}

# ─── CloudFront ───────────────────────────────────────────────────────────────

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution in front of ALB"
  type        = bool
}

variable "cloudfront_origin_verify_secret" {
  description = "Secret value sent from CloudFront to ALB in X-Origin-Verify header"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100 = US/EU cheapest)"
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for custom CloudFront domain"
  type        = string
  default     = ""
}

# ─── EKS ─────────────────────────────────────────────────────────────────────

variable "enable_eks" {
  description = "Enable EKS cluster"
  type        = bool
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.31"
}

variable "eks_api_server_allowed_cidrs" {
  description = "IP whitelist for EKS public API server — only these CIDRs can run kubectl"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min_size" {
  description = "Minimum worker nodes"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Maximum worker nodes"
  type        = number
  default     = 3
}

variable "eks_node_desired_size" {
  description = "Desired worker nodes"
  type        = number
  default     = 1
}

variable "eks_use_spot" {
  description = "Use SPOT instances for EKS nodes"
  type        = bool
  default     = false
}
