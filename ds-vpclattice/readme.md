## Important Notes on IAM Auth Policy
- When auth_type = "AWS_IAM", every request to the Lattice service must be signed with AWS SigV4 (e.g., using AWS credentials or an IAM role).

- The auth_policy is a resource‑based IAM policy attached to the service. It defines which IAM principals (roles, users, or accounts) can invoke the service.

- The policy must include the vpc-lattice-svcs:Invoke action. The Resource can be "*" or the specific service ARN (which you can obtain from the lattice_service_id output).

- If no auth_policy is provided but auth_type = "AWS_IAM", Terraform will fail validation (the module ensures a policy is present).

- For auth_type = "NONE", the auth_policy is ignored (set to null).

This module now gives you fine‑grained IAM access control for your ECS‑based services exposed through VPC Lattice.

### Example
```
module "secure_app" {
  source = "./modules/ecs-lattice-exposure"

  name_prefix         = "secureapp"
  ecs_cluster_name    = "prod-cluster"
  task_family         = "secureapp-task"
  container_definitions = [
    {
      name  = "app"
      image = "nginx:latest"
      portMappings = [{ containerPort = 80, protocol = "tcp" }]
    }
  ]
  execution_role_arn = "arn:aws:iam::123456789012:role/ecsExecutionRole"
  vpc_id             = "vpc-abc123"
  subnet_ids         = ["subnet-111", "subnet-222"]
  security_group_ids = ["sg-333"]

  # Enable IAM authentication
  lattice_auth_type = "AWS_IAM"
  lattice_auth_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::123456789012:role/MyServiceRole",
            "arn:aws:iam::123456789012:role/AnotherRole"
          ]
        }
        Action   = "vpc-lattice-svcs:Invoke"
        Resource = "*"  # or the specific service ARN
      }
    ]
  })

  lattice_listener_port     = 8080
  lattice_target_group_port = 80
  lattice_health_check_path = "/health"
}
```