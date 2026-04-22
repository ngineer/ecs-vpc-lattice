## DS VPCLattice Module

### Important Notes
- Provider Version: The module requires AWS provider ≥ 6.30.0, which introduced support for VPC Lattice target groups in aws_ecs_service.load_balancer.

- Target Type:

    - For bridge network mode → target_type = "instance"

    - For awsvpc network mode → target_type = "ip"

- Zero‑Trust Policy: The lattice_auth_policy variable expects a valid IAM policy document. You can scope access to specific IAM roles, users, or accounts.

- ECS Cluster: Not created by this module; it must already exist.

- Task Role: If your containers need to call other VPC Lattice services, attach the necessary permissions to task_role_arn.

## Usage Example

```
module "my_app" {
  source = "./ecs-lattice-module"

  # ECS
  cluster_name         = "my-ecs-cluster"
  service_name         = "my-app-service"
  task_family          = "my-app"
  container_definitions = jsonencode([
    {
      name  = "app"
      image = "nginx:latest"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 0 # dynamic host port (bridge mode)
        }
      ]
    }
  ])
  execution_role_arn = "arn:aws:iam::123456789012:role/ecsExecutionRole"
  network_mode       = "bridge"
  desired_count      = 2

  capacity_provider_strategies = [
    {
      capacity_provider = "my-capacity-provider"
      weight            = 1
      base              = 1
    }
  ]

  # VPC Lattice
  vpc_lattice_service_network_id = "sn-1234567890abcdef0"
  lattice_service_name           = "my-app-lattice"
  target_group_name              = "my-app-tg"
  target_group_port              = 80
  target_group_vpc_id            = "vpc-1234567890abcdef0"
  target_type                    = "instance" # because of bridge mode

  health_check = {
    path = "/health"
  }

  # Zero‑trust auth policy (example: allow only a specific IAM role)
  lattice_auth_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:role/trusted-caller"
        }
        Action   = "vpc-lattice-svcs:Invoke"
        Resource = "*"
      }
    ]
  })

  tags = {
    Environment = "production"
  }
}
```