variable "name" {
  description = "Base name used for the ECS service, task definition, VPC Lattice service, listener, and target group."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster."
  type        = string
}

variable "service_network_id" {
  description = "ID or ARN of the existing VPC Lattice service network to associate the service with."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ECS tasks run and where the VPC Lattice target group is created."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the ECS service tasks."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups attached to the ECS tasks."
  type        = list(string)
}

variable "container_name" {
  description = "Container name used in the task definition and ECS service load balancer block."
  type        = string
}

variable "container_image" {
  description = "Container image URI."
  type        = string
}

variable "container_port" {
  description = "Application port exposed by the container and used by the VPC Lattice target group."
  type        = number
}

variable "cpu" {
  description = "Fargate CPU units for the task definition."
  type        = string
  default     = "256"
}

variable "memory" {
  description = "Fargate memory for the task definition."
  type        = string
  default     = "512"
}

variable "task_role_arn" {
  description = "Optional IAM role ARN for the task."
  type        = string
  default     = null
}

variable "execution_role_arn" {
  description = "IAM role ARN for the task execution role."
  type        = string
}

variable "desired_count" {
  description = "Desired number of running tasks."
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = "Whether to assign public IPs to the ECS tasks."
  type        = bool
  default     = false
}

variable "platform_version" {
  description = "ECS Fargate platform version."
  type        = string
  default     = "LATEST"
}

variable "enable_execute_command" {
  description = "Whether to enable ECS Exec."
  type        = bool
  default     = false
}

variable "container_environment" {
  description = "Environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "container_secrets" {
  description = "Secrets for the container, as a list of objects with name and valueFrom."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "log_group_name" {
  description = "Optional CloudWatch log group name. If null, a log group is not created."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Retention in days for the CloudWatch log group."
  type        = number
  default     = 30
}

variable "service_auth_type" {
  description = "VPC Lattice auth type for the service."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.service_auth_type)
    error_message = "service_auth_type must be NONE or AWS_IAM."
  }
}

variable "listener_port" {
  description = "Listener port for the VPC Lattice service."
  type        = number
  default     = 80
}

variable "listener_protocol" {
  description = "Listener protocol for the VPC Lattice service."
  type        = string
  default     = "HTTP"
}

variable "target_group_protocol" {
  description = "Protocol for the VPC Lattice target group."
  type        = string
  default     = "HTTP"
}

variable "target_group_protocol_version" {
  description = "Protocol version for the VPC Lattice target group."
  type        = string
  default     = "HTTP1"
}

variable "target_group_ip_address_type" {
  description = "IP address type used by the VPC Lattice target group."
  type        = string
  default     = "IPV4"
}

variable "health_check" {
  description = "Optional health check configuration for the VPC Lattice target group."
  type = object({
    enabled                     = optional(bool, true)
    path                        = optional(string, "/")
    port                        = optional(number)
    protocol                    = optional(string, "HTTP")
    protocol_version            = optional(string, "HTTP1")
    matcher                     = optional(string, "200-399")
    health_check_interval_seconds = optional(number, 30)
    health_check_timeout_seconds  = optional(number, 5)
    healthy_threshold_count     = optional(number, 2)
    unhealthy_threshold_count   = optional(number, 2)
  })
  default = {}
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
