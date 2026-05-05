variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name used as CloudFront origin"
  type        = string
}

variable "origin_verify_secret" {
  description = "Secret value in X-Origin-Verify header — ALB should validate this to block direct access"
  type        = string
  sensitive   = true
}

variable "acm_certificate_arn" {
  description = "ACM cert ARN in us-east-1 for custom domain (leave empty to use CloudFront default cert)"
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront price class: PriceClass_All, PriceClass_200, PriceClass_100"
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
