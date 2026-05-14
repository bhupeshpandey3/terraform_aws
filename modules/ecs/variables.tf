variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks. Private subnets when NAT is enabled; public subnets when NAT is disabled."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IPs to ECS tasks. Required when tasks run in public subnets (i.e. no NAT gateway)."
  type        = bool
  default     = false
}

variable "alb_target_group_arn" {
  description = "ALB target group ARN. Empty string disables ALB integration."
  type        = string
  default     = ""
}

variable "alb_security_group_id" {
  description = "ALB security group ID. Empty string disables ALB ingress rule."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "HTTP path for container health check"
  type        = string
  default     = "/"
}

variable "launch_type" {
  description = "ECS launch type: FARGATE or EC2"
  type        = string
  default     = "FARGATE"
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Container image URI"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
}

variable "container_cpu" {
  description = "Task CPU units"
  type        = number
}

variable "container_memory" {
  description = "Task memory in MiB"
  type        = number
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN the task role can access. Empty string disables S3 policy."
  type        = string
  default     = ""
}

variable "db_endpoint" {
  description = "RDS endpoint injected as DB_ENDPOINT env var. Empty string when RDS is disabled."
  type        = string
  default     = ""
}

variable "container_environment" {
  description = "Extra environment variables injected into the ECS container (list of {name, value} objects)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
