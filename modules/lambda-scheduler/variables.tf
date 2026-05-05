variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name to manage"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name to manage"
  type        = string
}

variable "schedule_stop_cron" {
  description = "EventBridge cron to stop the service (UTC)"
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "schedule_start_cron" {
  description = "EventBridge cron to start the service (UTC)"
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "schedule_desired_count" {
  description = "Desired task count to set on start"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
