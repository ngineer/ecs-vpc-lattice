# --- ECS ---
variable "cluster_name" {
  description = "Name of the existing ECS cluster"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service to create"
  type        = string
}

variable "task_family" {
  description = "Family name for the ECS task definition"
  type        = string
}

variable "container_definitions" {
  description = "JSON-encoded list of container definitions for the task"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN for the ECS task (optional)"
  type        = string
  default     = null
}

variable "execution_role_arn" {
  description = "IAM role ARN for ECS task execution"
  type        = string
}

variable "network_mode" {
  description = "Network mode for the task (bridge, awsvpc, etc.)"
  type        = string
  default     = "bridge"
  validation {
    condition     = contains(["bridge", "awsvpc", "host", "none"], var.network_mode)
    error_message = "Valid values: bridge, awsvpc, host, none"
  }
}

variable "cpu" {
  description = "CPU units for the task (e.g., 256, 512)"
  type        = string
  default     = null
}

variable "memory" {
  description = "Memory in MiB for the task (e.g., 512, 1024)"
  type        = string
  default     = null
}

variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
}

variable "deployment_maximum_percent" {
  description = "Upper limit of tasks during deployment"
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower limit of tasks during deployment"
  type        = number
  default     = 100
}

variable "capacity_provider_strategies" {
  description = "List of capacity provider strategies (for EC2 launch type)"
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 1)
  }))
  default = []
}

variable "ordered_placement_strategies" {
  description = "Placement strategies for tasks"
  type = list(object({
    type  = string
    field = optional(string)
  }))
  default = []
}

# --- Networking (for awsvpc mode) ---
variable "subnets" {
  description = "List of subnet IDs for the ECS service (required if network_mode = awsvpc)"
  type        = list(string)
  default     = []
}

variable "security_groups" {
  description = "List of security group IDs for the ECS service (required if network_mode = awsvpc)"
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks (only for awsvpc)"
  type        = bool
  default     = false
}

# --- VPC Lattice ---
variable "vpc_lattice_service_network_id" {
  description = "ID of the VPC Lattice service network to associate with"
  type        = string
}

variable "lattice_service_name" {
  description = "Name for the VPC Lattice service"
  type        = string
}

variable "lattice_auth_type" {
  description = "Auth type for the VPC Lattice service (NONE or AWS_IAM)"
  type        = string
  default     = "AWS_IAM"
}

variable "lattice_auth_policy" {
  description = "IAM policy document (JSON) for VPC Lattice auth policy (required if auth_type = AWS_IAM)"
  type        = string
  default     = null
}

variable "target_group_name" {
  description = "Name of the VPC Lattice target group"
  type        = string
}

variable "target_group_port" {
  description = "Port on which the containers listen"
  type        = number
}

variable "target_group_protocol" {
  description = "Protocol for the target group (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
}

variable "target_group_vpc_id" {
  description = "VPC ID where targets reside (required for VPC Lattice target group)"
  type        = string
}

variable "target_type" {
  description = "Target type: 'instance' for bridge networking, 'ip' for awsvpc"
  type        = string
  default     = "instance"
  validation {
    condition     = contains(["instance", "ip"], var.target_type)
    error_message = "Valid values: instance, ip"
  }
}

variable "health_check" {
  description = "Health check configuration for the target group"
  type = object({
    enabled             = optional(bool, true)
    interval_seconds    = optional(number, 30)
    path                = optional(string, "/")
    port                = optional(string) # if not set, uses traffic port
    protocol            = optional(string, "HTTP")
    timeout_seconds     = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 2)
    matcher             = optional(string, "200-299")
  })
  default = {}
}

variable "listener_port" {
  description = "Port for the VPC Lattice listener"
  type        = number
  default     = 80
}

variable "listener_protocol" {
  description = "Protocol for the VPC Lattice listener (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
}

# --- Tags ---
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}