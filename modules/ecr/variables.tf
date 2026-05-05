variable "name_prefix" {
  description = "Name prefix for ECR repository paths"
  type        = string
}

variable "repositories" {
  description = "List of service names to create ECR repos for (e.g. [\"backend\", \"frontend\"])"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
