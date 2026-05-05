locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }

  # EKS subnet tags injected into VPC when EKS is enabled
  eks_cluster_name = "${local.name_prefix}-eks"

  public_subnet_extra_tags = var.enable_eks ? {
    "kubernetes.io/role/elb"                          = "1"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  } : {}

  private_subnet_extra_tags = var.enable_eks ? {
    "kubernetes.io/role/internal-elb"                 = "1"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  } : {}
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix               = local.name_prefix
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_subnet_cidrs      = var.private_subnet_cidrs
  enable_nat_gateway        = var.enable_nat_gateway
  public_subnet_extra_tags  = local.public_subnet_extra_tags
  private_subnet_extra_tags = local.private_subnet_extra_tags
  tags                      = local.common_tags
}

module "s3" {
  source = "./modules/s3"
  count  = var.enable_s3 ? 1 : 0

  bucket_name        = var.s3_bucket_name
  versioning_enabled = var.s3_versioning_enabled
  tags               = local.common_tags
}

module "ecr" {
  source = "./modules/ecr"
  count  = var.enable_ecr ? 1 : 0

  name_prefix  = local.name_prefix
  repositories = var.ecr_repositories
  tags         = local.common_tags
}

module "alb" {
  source = "./modules/alb"
  count  = var.enable_alb ? 1 : 0

  name_prefix                = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  internal                   = var.alb_internal
  container_port             = var.container_port
  health_check_path          = var.health_check_path
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = var.environment == "prod"
  tags                       = local.common_tags
}

module "rds" {
  source = "./modules/rds"
  count  = var.enable_rds ? 1 : 0

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  ecs_security_group_id   = try(module.ecs[0].ecs_security_group_id, "")
  db_engine               = var.db_engine
  db_engine_version       = var.db_engine_version
  db_instance_class       = var.db_instance_class
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  db_allocated_storage    = var.db_allocated_storage
  multi_az                = var.db_multi_az
  deletion_protection     = var.db_deletion_protection
  backup_retention_period = var.db_backup_retention_period
  tags                    = local.common_tags
}

module "ecs" {
  source = "./modules/ecs"
  count  = var.enable_ecs ? 1 : 0

  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  # No NAT: tasks run in public subnets with a public IP so they can reach the internet.
  # NAT enabled: tasks run in private subnets behind the NAT gateway (prod default).
  subnet_ids            = var.enable_nat_gateway ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids
  assign_public_ip      = !var.enable_nat_gateway
  alb_target_group_arn  = try(module.alb[0].target_group_arn, "")
  alb_security_group_id = try(module.alb[0].alb_security_group_id, "")
  launch_type           = var.ecs_launch_type
  desired_count         = var.ecs_desired_count
  container_image = var.enable_ecr ? coalesce(
    try(module.ecr[0].repository_urls["backend"], ""),
    try(module.ecr[0].repository_urls["app"], ""),
    var.container_image
  ) : var.container_image
  container_port        = var.container_port
  container_cpu         = var.container_cpu
  container_memory      = var.container_memory
  s3_bucket_arn         = try(module.s3[0].bucket_arn, "")
  db_endpoint           = try(module.rds[0].db_endpoint, "")
  health_check_path     = var.health_check_path
  tags                  = local.common_tags
}

module "ec2" {
  source = "./modules/ec2"
  count  = var.ecs_launch_type == "EC2" && var.enable_ecs ? 1 : 0

  name_prefix           = local.name_prefix
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_cluster_name      = try(module.ecs[0].cluster_name, "")
  ecs_security_group_id = try(module.ecs[0].ecs_security_group_id, "")
  instance_type         = var.ec2_instance_type
  desired_capacity      = var.ec2_desired_capacity
  min_size              = var.ec2_min_size
  max_size              = var.ec2_max_size
  tags                  = local.common_tags
}

module "lambda_scheduler" {
  source = "./modules/lambda-scheduler"
  count  = var.enable_scheduler && var.enable_ecs ? 1 : 0

  name_prefix            = local.name_prefix
  ecs_cluster_name       = try(module.ecs[0].cluster_name, "")
  ecs_service_name       = try(module.ecs[0].service_name, "")
  schedule_stop_cron     = var.schedule_stop_cron
  schedule_start_cron    = var.schedule_start_cron
  schedule_desired_count = var.schedule_desired_count
  tags                   = local.common_tags
}

module "cloudfront" {
  source = "./modules/cloudfront"
  count  = var.enable_cloudfront && var.enable_alb ? 1 : 0

  name_prefix          = local.name_prefix
  alb_dns_name         = try(module.alb[0].alb_dns_name, "")
  origin_verify_secret = var.cloudfront_origin_verify_secret
  acm_certificate_arn  = var.cloudfront_acm_certificate_arn
  price_class          = var.cloudfront_price_class
  tags                 = local.common_tags
}

module "eks" {
  source = "./modules/eks"
  count  = var.enable_eks ? 1 : 0

  name_prefix              = local.name_prefix
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  public_subnet_ids        = module.vpc.public_subnet_ids
  cluster_version          = var.eks_cluster_version
  api_server_allowed_cidrs = var.eks_api_server_allowed_cidrs
  node_instance_type       = var.eks_node_instance_type
  node_min_size            = var.eks_node_min_size
  node_max_size            = var.eks_node_max_size
  node_desired_size        = var.eks_node_desired_size
  use_spot                 = var.eks_use_spot
  tags                     = local.common_tags
}
