environment  = "staging"
project_name = "myapp"
aws_region   = "us-east-1"

# Staging-specific feature overrides
enable_nat_gateway = true
enable_scheduler   = true

# ECR repos
ecr_repositories = ["backend", "frontend"]

# VPC
vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

# ECS
ecs_launch_type   = "FARGATE"
ecs_desired_count = 2
container_image   = "nginx:latest"
container_port    = 80
container_cpu     = 512
container_memory  = 1024

# RDS
db_engine                  = "mysql"
db_engine_version          = "8.0"
db_instance_class          = "db.t3.small"
db_name                    = "myappdb"
db_username                = "admin"
db_password                = "ChangeMe123!"
db_allocated_storage       = 50
db_multi_az                = false
db_deletion_protection     = true
db_backup_retention_period = 7

# S3
s3_bucket_name        = "myapp-staging-assets-a1b2c3"
s3_versioning_enabled = true

# ALB
alb_internal      = false
health_check_path = "/health"
certificate_arn   = ""

# Scheduler
schedule_stop_cron     = "cron(0 20 ? * MON-FRI *)"
schedule_start_cron    = "cron(0 8 ? * MON-FRI *)"
schedule_desired_count = 2

# CloudFront
cloudfront_origin_verify_secret = "staging-secret-change-me"
cloudfront_price_class          = "PriceClass_100"
cloudfront_acm_certificate_arn  = ""

# EKS
eks_cluster_version          = "1.31"
eks_api_server_allowed_cidrs = ["0.0.0.0/0"]
eks_node_instance_type       = "t3.medium"
eks_node_min_size            = 1
eks_node_max_size            = 3
eks_node_desired_size        = 1
eks_use_spot                 = false
