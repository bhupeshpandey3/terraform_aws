variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "public_subnet_extra_tags" {
  description = "Extra tags for public subnets (e.g. EKS elb tags)"
  type        = map(string)
  default     = {}
}

variable "private_subnet_extra_tags" {
  description = "Extra tags for private subnets (e.g. EKS internal-elb tags)"
  type        = map(string)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateways so private subnets can reach the internet. Disable in dev to save ~$65/month; use VPC endpoints instead."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
