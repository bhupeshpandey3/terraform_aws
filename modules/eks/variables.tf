variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for worker nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for control plane ENIs"
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "api_server_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to access the EKS public API server (e.g. [\"203.0.113.10/32\"]). EKS does not support IPv6 CIDRs here."
  type        = list(string)

  validation {
    condition     = length(var.api_server_allowed_cidrs) > 0
    error_message = "At least one IPv4 CIDR must be provided. EKS publicAccessCidrs only accepts IPv4."
  }

  validation {
    condition     = alltrue([for c in var.api_server_allowed_cidrs : !can(regex(":", c))])
    error_message = "All CIDRs must be IPv4 (e.g. 1.2.3.4/32). IPv6 CIDRs are not supported by EKS publicAccessCidrs."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "use_spot" {
  description = "Use SPOT instances for worker nodes (cheaper but interruptible)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
