locals {
  log_group_name = coalesce(var.log_group_name, "/ecs/${var.name}")
  common_tags    = var.tags

  task_container_definitions = [
    merge(
      {
        name      = var.container_name
        image     = var.container_image
        essential = true

        portMappings = [
          {
            containerPort = var.container_port
            protocol      = "tcp"
          }
        ]

        environment = [
          for k, v in var.container_environment : {
            name  = k
            value = v
          }
        ]

        secrets = [
          for s in var.container_secrets : {
            name      = s.name
            valueFrom = s.valueFrom
          }
        ]
      },
      length(aws_cloudwatch_log_group.this) > 0 ? {
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.this[0].name
            awslogs-region        = data.aws_region.current.name
            awslogs-stream-prefix = var.name
          }
        }
      } : {}
    )
  ]
}

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  count             = var.log_group_name == null ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  tags              = local.common_tags
}

resource "aws_vpclattice_service" "this" {
  name      = var.name
  auth_type = var.service_auth_type
  tags      = local.common_tags
}

resource "aws_vpclattice_target_group" "this" {
  name = var.name
  type = "IP"

  config {
    port              = var.container_port
    protocol          = var.target_group_protocol
    vpc_identifier    = var.vpc_id
    ip_address_type   = var.target_group_ip_address_type
    protocol_version  = var.target_group_protocol_version

    dynamic "health_check" {
      for_each = [var.health_check]
      content {
        enabled                      = try(health_check.value.enabled, true)
        path                         = try(health_check.value.path, null)
        port                         = try(health_check.value.port, null)
        protocol                     = try(health_check.value.protocol, null)
        protocol_version             = try(health_check.value.protocol_version, null)
        matcher {
          value = try(health_check.value.matcher, null)
        }
        health_check_interval_seconds = try(health_check.value.health_check_interval_seconds, null)
        health_check_timeout_seconds   = try(health_check.value.health_check_timeout_seconds, null)
        healthy_threshold_count        = try(health_check.value.healthy_threshold_count, null)
        unhealthy_threshold_count      = try(health_check.value.unhealthy_threshold_count, null)
      }
    }
  }

  tags = local.common_tags
}

resource "aws_vpclattice_listener" "this" {
  name               = var.name
  service_identifier  = aws_vpclattice_service.this.id
  protocol           = var.listener_protocol
  port               = var.listener_port

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this.arn
        weight                  = 100
      }
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode(local.task_container_definitions)

  tags = local.common_tags
}

resource "aws_ecs_service" "this" {
  name                               = var.name
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = var.platform_version
  enable_execute_command             = var.enable_execute_command
  health_check_grace_period_seconds  = 60

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_vpclattice_target_group.this.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  depends_on = [
    aws_vpclattice_listener.this
  ]

  tags = local.common_tags
}

resource "aws_vpclattice_service_network_service_association" "this" {
  service_identifier         = aws_vpclattice_service.this.id
  service_network_identifier = var.service_network_id

  depends_on = [
    aws_ecs_service.this,
    aws_vpclattice_listener.this
  ]

  tags = local.common_tags
}
