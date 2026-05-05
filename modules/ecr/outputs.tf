output "repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = length(aws_ecr_repository.this) > 0 ? one(values(aws_ecr_repository.this)).registry_id : ""
}
