# ------------------------------------------------------------------------------
# ECS Task Definition
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  container_definitions    = var.container_definitions
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  network_mode             = var.network_mode
  cpu                      = var.cpu
  memory                   = var.memory
  requires_compatibilities = ["EC2"]

  tags = var.tags
}

# ------------------------------------------------------------------------------
# VPC Lattice Target Group
# ------------------------------------------------------------------------------
resource "aws_vpclattice_target_group" "this" {
  name = var.target_group_name
  type = var.target_type

  config {
    port             = var.target_group_port
    protocol         = var.target_group_protocol
    vpc_identifier   = var.target_group_vpc_id

    dynamic "health_check" {
      for_each = var.health_check.enabled ? [1] : []
      content {
        enabled             = true
        interval_seconds    = var.health_check.interval_seconds
        path                = var.health_check.path
        port                = var.health_check.port
        protocol            = var.health_check.protocol
        timeout_seconds     = var.health_check.timeout_seconds
        healthy_threshold   = var.health_check.healthy_threshold
        unhealthy_threshold = var.health_check.unhealthy_threshold
        matcher {
          value = var.health_check.matcher
        }
      }
    }
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# ECS Service (with load balancer attachment to VPC Lattice target group)
# ------------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  # Capacity provider strategy for EC2 launch type
  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  # Placement strategies (optional)
  dynamic "ordered_placement_strategy" {
    for_each = var.ordered_placement_strategies
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  # Network configuration for awsvpc mode
  dynamic "network_configuration" {
    for_each = var.network_mode == "awsvpc" ? [1] : []
    content {
      subnets          = var.subnets
      security_groups  = var.security_groups
      assign_public_ip = var.assign_public_ip
    }
  }

  # Attach the VPC Lattice target group so that ECS auto‑registers tasks
  load_balancer {
    target_group_arn = aws_vpclattice_target_group.this.arn
    container_name   = jsondecode(var.container_definitions)[0].name
    container_port   = var.target_group_port
  }

  # Allow external changes to desired count without Terraform resetting it
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# VPC Lattice Service
# ------------------------------------------------------------------------------
resource "aws_vpclattice_service" "this" {
  name      = var.lattice_service_name
  auth_type = var.lattice_auth_type

  tags = var.tags
}

# ------------------------------------------------------------------------------
# VPC Lattice Auth Policy (IAM‑based zero trust)
# ------------------------------------------------------------------------------
resource "aws_vpclattice_auth_policy" "this" {
  count = var.lattice_auth_type == "AWS_IAM" && var.lattice_auth_policy != null ? 1 : 0

  resource_identifier = aws_vpclattice_service.this.arn
  policy              = var.lattice_auth_policy
}

# ------------------------------------------------------------------------------
# VPC Lattice Listener
# ------------------------------------------------------------------------------
resource "aws_vpclattice_listener" "this" {
  name               = "${var.lattice_service_name}-listener"
  protocol           = var.listener_protocol
  port               = var.listener_port
  service_identifier = aws_vpclattice_service.this.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this.id
        weight                  = 100
      }
    }
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# VPC Lattice Service Network Association
# ------------------------------------------------------------------------------
resource "aws_vpclattice_service_network_service_association" "this" {
  service_identifier         = aws_vpclattice_service.this.id
  service_network_identifier = var.vpc_lattice_service_network_id

  tags = var.tags
}