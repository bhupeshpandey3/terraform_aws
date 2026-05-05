environment  = "prod"
project_name = "myapp"
aws_region   = "us-east-1"

# Prod-specific feature overrides
enable_nat_gateway = true
enable_scheduler   = false   # prod runs 24/7

# ECR repos
ecr_repositories = ["backend", "frontend"]

# VPC (3 AZs for HA)
vpc_cidr             = "10.2.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]

# ECS (production sizing)
ecs_launch_type   = "FARGATE"
ecs_desired_count = 3
container_image   = "nginx:latest"
container_port    = 80
container_cpu     = 1024
container_memory  = 2048

# EC2 (if switching to EC2 launch type)
ec2_instance_type    = "t3.large"
ec2_desired_capacity = 3
ec2_min_size         = 2
ec2_max_size         = 10

# RDS (production sizing)
db_engine                  = "mysql"
db_engine_version          = "8.0"
db_instance_class          = "db.r6g.large"
db_name                    = "myappdb"
db_username                = "admin"
db_password                = "ChangeMe123!"
db_allocated_storage       = 100
db_multi_az                = true
db_deletion_protection     = true
db_backup_retention_period = 14

# S3
s3_bucket_name        = "myapp-prod-assets-a1b2c3"
s3_versioning_enabled = true

# ALB
alb_internal      = false
health_check_path = "/health"
certificate_arn   = ""

# Scheduler (disabled but crons kept for reference)
schedule_stop_cron     = "cron(0 20 * * ? *)"
schedule_start_cron    = "cron(0 8 * * ? *)"
schedule_desired_count = 3

# CloudFront
cloudfront_origin_verify_secret = "prod-secret-change-me"
cloudfront_price_class          = "PriceClass_100"
cloudfront_acm_certificate_arn  = ""

# EKS
eks_cluster_version          = "1.31"
eks_api_server_allowed_cidrs = ["0.0.0.0/0"]
eks_node_instance_type       = "t3.large"
eks_node_min_size            = 2
eks_node_max_size            = 6
eks_node_desired_size        = 2
eks_use_spot                 = false
