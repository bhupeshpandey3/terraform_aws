environment  = "dev"
project_name = "myapp"
aws_region   = "us-east-2"

# Dev-specific feature overrides (stack sets the baseline)
enable_s3         = true
enable_alb        = true
enable_rds        = false
enable_ecs        = true
enable_ecr        = true
enable_cloudfront = false
enable_eks        = false
enable_nat_gateway = false   # saves ~$65/month in dev
enable_scheduler   = true

# ECR repos for this project
ecr_repositories = ["backend", "frontend"]

# VPC
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-2a", "us-east-2b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# ECS (small in dev)
ecs_launch_type   = "FARGATE"
ecs_desired_count = 1
container_image   = "nginx:latest"
container_port    = 80
container_cpu     = 256
container_memory  = 512

# RDS (minimal in dev)
db_engine                  = "mysql"
db_engine_version          = "8.0"
db_instance_class          = "db.t3.micro"
db_name                    = "myappdb"
db_username                = "admin"
db_password                = "ChangeMe123!"
db_allocated_storage       = 20
db_multi_az                = false
db_deletion_protection     = false
db_backup_retention_period = 1

# S3
s3_bucket_name        = "myapp-dev-assets-a1b2c3"
s3_versioning_enabled = true

# ALB
alb_internal      = false
health_check_path = "/"
certificate_arn   = ""

# Scheduler
schedule_stop_cron     = "cron(0 19 ? * MON-FRI *)"
schedule_start_cron    = "cron(0 7 ? * MON-FRI *)"
schedule_desired_count = 1

# CloudFront
cloudfront_origin_verify_secret = "dev-secret-change-in-prod-abc123"
cloudfront_price_class          = "PriceClass_100"
cloudfront_acm_certificate_arn  = ""

# EKS
eks_cluster_version          = "1.31"
eks_api_server_allowed_cidrs = ["0.0.0.0/0"]
eks_node_instance_type       = "t3.medium"
eks_node_min_size            = 1
eks_node_max_size            = 2
eks_node_desired_size        = 1
eks_use_spot                 = false
