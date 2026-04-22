# ------------------------------------------------------------------------------
# MODULE: ecs-lattice-exposure (with IAM auth policy)
# ------------------------------------------------------------------------------

# ------------------------------------------------------------
# Variable declarations (new ones added)
# ------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix used for naming resources"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of an existing ECS cluster"
  type        = string
}

variable "task_family" {
  description = "Family name for the ECS task definition"
  type        = string
}

variable "container_definitions" {
  description = "JSON or list of container definitions"
  type        = any
}

variable "task_cpu" {
  description = "CPU units for the task (e.g., 256, 512)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory for the task in MiB"
  type        = number
  default     = 512
}

variable "execution_role_arn" {
  description = "IAM role ARN for ECS task execution (required for Fargate)"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN for the task containers"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID where the ECS service and Lattice resources are deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ECS service (list of private/public subnets)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the ECS service tasks"
  type        = list(string)
}

variable "service_desired_count" {
  description = "Number of desired tasks"
  type        = number
  default     = 1
}

# Lattice related variables
variable "lattice_service_network_id" {
  description = "ID of an existing VPC Lattice service network. If empty, a new service network is created."
  type        = string
  default     = null
}

variable "lattice_service_name" {
  description = "Name of the VPC Lattice service (if not set, uses name_prefix)"
  type        = string
  default     = null
}

variable "lattice_listener_port" {
  description = "Port on which the Lattice service listens"
  type        = number
  default     = 80
}

variable "lattice_listener_protocol" {
  description = "Protocol for the Lattice listener (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
  validation {
    condition     = var.lattice_listener_protocol == "HTTP" || var.lattice_listener_protocol == "HTTPS"
    error_message = "Protocol must be HTTP or HTTPS."
  }
}

variable "lattice_target_group_port" {
  description = "Port on which the ECS tasks are listening (used for health checks)"
  type        = number
  default     = 80
}

variable "lattice_target_group_protocol" {
  description = "Protocol for the Lattice target group (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
  validation {
    condition     = var.lattice_target_group_protocol == "HTTP" || var.lattice_target_group_protocol == "HTTPS"
    error_message = "Protocol must be HTTP or HTTPS."
  }
}

variable "lattice_health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"
}

variable "create_vpc_association" {
  description = "Whether to associate the VPC with the Lattice service network"
  type        = bool
  default     = true
}

# NEW: IAM authentication for the Lattice service
variable "lattice_auth_type" {
  description = "Authentication type for the VPC Lattice service: 'NONE' or 'AWS_IAM'"
  type        = string
  default     = "NONE"
  validation {
    condition     = var.lattice_auth_type == "NONE" || var.lattice_auth_type == "AWS_IAM"
    error_message = "auth_type must be either 'NONE' or 'AWS_IAM'."
  }
}

variable "lattice_auth_policy" {
  description = "IAM policy document (JSON string) for the Lattice service. Required if auth_type is 'AWS_IAM'."
  type        = string
  default     = null
}

# ------------------------------------------------------------
# ECS Task Definition
# ------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode(var.container_definitions)
}

# ------------------------------------------------------------
# ECS Service
# ------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name                               = "${var.name_prefix}-service"
  cluster                            = var.ecs_cluster_name
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.service_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 60

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [
      task_definition
    ]
  }
}

# ------------------------------------------------------------
# VPC Lattice Service Network
# ------------------------------------------------------------
resource "aws_vpclattice_service_network" "this" {
  count = var.lattice_service_network_id == null ? 1 : 0
  name  = "${var.name_prefix}-service-network"
}

locals {
  service_network_id = var.lattice_service_network_id != null ? var.lattice_service_network_id : aws_vpclattice_service_network.this[0].id
}

# ------------------------------------------------------------
# VPC Lattice Target Group (ECS)
# ------------------------------------------------------------
resource "aws_vpclattice_target_group" "this" {
  name        = "${var.name_prefix}-tg"
  type        = "ECS"
#   vpc_identifier = var.vpc_id

  config {
    port           = var.lattice_target_group_port
    protocol       = var.lattice_target_group_protocol
    protocol_version = "HTTP1"
    health_check {
      enabled                = true
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 3
      unhealthy_threshold_count     = 3
      path                          = var.lattice_health_check_path
      protocol                      = var.lattice_target_group_protocol
    }
  }
}

# ------------------------------------------------------------
# VPC Lattice Service (with optional IAM auth policy)
# ------------------------------------------------------------
resource "aws_vpclattice_service" "this" {
  name           = coalesce(var.lattice_service_name, "${var.name_prefix}-service")
  auth_type      = var.lattice_auth_type
#   auth_policy    = var.lattice_auth_type == "AWS_IAM" ? var.lattice_auth_policy : null
  custom_domain_name = null
}

# ------------------------------------------------------------
# VPC Lattice Listener
# ------------------------------------------------------------
resource "aws_vpclattice_listener" "this" {
  name               = "${var.name_prefix}-listener"
  service_identifier = aws_vpclattice_service.this.id
  protocol           = var.lattice_listener_protocol
  port               = var.lattice_listener_port

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this.id
        weight                  = 100
      }
    }
  }
}

# ------------------------------------------------------------
# Service Network ↔ VPC Association
# ------------------------------------------------------------
resource "aws_vpclattice_service_network_vpc_association" "this" {
  count = var.create_vpc_association ? 1 : 0

  service_network_identifier = local.service_network_id
  vpc_identifier             = var.vpc_id
  security_group_ids         = var.security_group_ids
}

# ------------------------------------------------------------
# Service Network ↔ Service Association
# ------------------------------------------------------------
resource "aws_vpclattice_service_network_service_association" "this" {
  service_identifier         = aws_vpclattice_service.this.id
  service_network_identifier = local.service_network_id
}

# ------------------------------------------------------------
# Attach ECS Service to Lattice Target Group
# ------------------------------------------------------------
resource "aws_vpclattice_target_group_attachment" "this" {
  target_group_identifier = aws_vpclattice_target_group.this.id

  target {
    id = aws_ecs_service.this.id
  }
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "ecs_service_id" {
  description = "ID (ARN) of the ECS service"
  value       = aws_ecs_service.this.id
}

output "lattice_service_network_id" {
  description = "ID of the VPC Lattice service network (existing or created)"
  value       = local.service_network_id
}

output "lattice_service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.this.id
}

output "lattice_service_dns_name" {
  description = "DNS name of the VPC Lattice service"
  value       = aws_vpclattice_service.this.dns_entry[0].domain_name
}

output "lattice_target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.this.id
}