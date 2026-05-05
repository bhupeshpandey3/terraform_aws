output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# ─── ALB ─────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = var.enable_alb ? module.alb[0].alb_dns_name : null
}

output "alb_zone_id" {
  description = "ALB hosted zone ID"
  value       = var.enable_alb ? module.alb[0].alb_zone_id : null
}

# ─── ECS ─────────────────────────────────────────────────────────────────────

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = var.enable_ecs ? module.ecs[0].cluster_name : null
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = var.enable_ecs ? module.ecs[0].service_name : null
}

# ─── RDS ─────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = var.enable_rds ? module.rds[0].db_endpoint : null
  sensitive   = true
}

output "rds_port" {
  description = "RDS port"
  value       = var.enable_rds ? module.rds[0].db_port : null
}

# ─── S3 ──────────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  description = "Application S3 bucket name"
  value       = var.enable_s3 ? module.s3[0].bucket_name : null
}

output "s3_bucket_arn" {
  description = "Application S3 bucket ARN"
  value       = var.enable_s3 ? module.s3[0].bucket_arn : null
}

# ─── CloudFront ───────────────────────────────────────────────────────────────

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = var.enable_cloudfront ? module.cloudfront[0].distribution_domain_name : null
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = var.enable_cloudfront ? module.cloudfront[0].distribution_id : null
}

# ─── EKS ─────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = var.enable_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "eks_kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = var.enable_eks ? module.eks[0].kubeconfig_command : null
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = var.enable_eks ? module.eks[0].oidc_provider_arn : null
}

# ─── ECR ─────────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = var.enable_ecr ? module.ecr[0].repository_urls : {}
}
