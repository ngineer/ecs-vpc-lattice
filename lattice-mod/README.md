# ECS on Fargate exposed through VPC Lattice

This module creates:

- an ECS task definition
- an ECS service
- a VPC Lattice service
- a VPC Lattice target group
- a VPC Lattice listener
- a VPC Lattice service-network association

The ECS service uses the VPC Lattice target group in its `load_balancer` block, and ECS automatically registers the task IPs into that target group when tasks start.

## Inputs

Provide an existing ECS cluster, an existing VPC Lattice service network, VPC subnets, task security groups, and IAM roles for the task execution role and optional task role.

## Example

```hcl
module "api_service" {
  source = "./modules/ecs-vpc-lattice"

  name                = "orders-api"
  cluster_arn         = aws_ecs_cluster.main.arn
  service_network_id   = aws_vpclattice_service_network.main.id
  vpc_id              = aws_vpc.main.id
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.ecs_tasks.id]

  container_name      = "orders-api"
  container_image     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api:latest"
  container_port      = 8080

  execution_role_arn  = aws_iam_role.ecs_execution.arn
  task_role_arn       = aws_iam_role.ecs_task.arn

  desired_count       = 2
  assign_public_ip    = false

  tags = {
    service = "orders-api"
    env     = "prod"
  }
}
```
