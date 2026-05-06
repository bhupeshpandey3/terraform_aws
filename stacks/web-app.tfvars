# Stack: web-app
# Use case: Standard web application — ECS Fargate behind ALB, RDS database, S3 storage
# Env overrides: enable_nat_gateway and enable_scheduler are set per environment

enable_s3         = true
enable_alb        = true
enable_rds        = false
enable_ecs        = true
enable_ecr        = true
enable_scheduler  = true
enable_cloudfront = false
enable_eks        = false
