# Executive Summary

This design provides a Terraform module that creates an **ECS service** (with Fargate tasks) and exposes it via **AWS VPC Lattice**. The module assumes an existing ECS cluster (ARN passed as input) and existing VPC Lattice Service Network and Service. It provisions the ECS **Task Definition** and **Service** with native VPC Lattice integration, including a VPC Lattice **Target Group**, **Listener**, and **Service-Network Association**. The ECS tasks register as *IP targets* in the Lattice target group, allowing Lattice to load-balance traffic to the tasks without requiring a traditional load balancer【18†L18-L24】. 

This approach leverages AWS’s native integration: ECS will automatically register/deregister task IPs in the Lattice target group and replace unhealthy tasks based on Lattice health checks【18†L18-L24】. It thus simplifies networking (no ALB needed) and provides built‑in security features (TLS enforcement, IAM‑based access control) that improve the security posture【18†L50-L58】【54†L1-L4】. The module enforces a “zero-trust” posture by using least-privilege IAM roles and requiring IAM (SigV4) authentication for service calls. It creates or accepts an **ECS infrastructure role** with only the permissions to manage VPC Lattice target groups (using the AWS‑managed `AmazonECSInfrastructureRolePolicyForVpcLattice`)【24†L28-L31】【31†L1-L4】. It also defines a **task execution role** (for pulling images and CloudWatch Logs) and a **task role** (for application code), attaching only necessary policies (e.g. `vpc-lattice-svcs:Invoke` to allow the task to call other Lattice services). On the network side, it recommends locking down security groups to allow inbound traffic **only from the VPC Lattice managed prefix list** on the service port【54†L1-L4】.

The deliverable below details the module’s design: required AWS resources (table), Terraform file structure and example usage, code snippets for each resource, IAM policy examples, a mermaid diagram of the architecture, and a security/testing checklist. All design choices reference AWS and Terraform documentation and security best practices.

## Design Overview: Resources and Purpose

| **Resource Type**                                | **Terraform Name (AWS)**                                         | **Purpose**                                                              |
|----------------------------------------------|----------------------------------------------------------|-------------------------------------------------------------------------|
| **ECS Task Definition**                      | `aws_ecs_task_definition`                            | Defines the container image, CPU/memory, ports, and logging for the task. |
| **CloudWatch Log Group**                     | `aws_cloudwatch_log_group`                           | Stores container logs (optionally created if not existing).               |
| **ECS Service**                              | `aws_ecs_service`                                    | Runs the desired count of tasks, in the specified subnets/security groups, with a VPC Lattice target group attached. |
| **VPC Lattice Target Group**                 | `aws_vpclattice_target_group`                        | Groups the ECS task IPs for load balancing by Lattice.                   |
| **VPC Lattice Listener**                     | `aws_vpclattice_listener`                            | Listens on a port for the Lattice service and forwards to the target group.|
| **VPC Lattice Service-Network Association**  | `aws_vpclattice_service_network_service_association` | Associates the Lattice Service with the Service Network (making it reachable by clients in the network). |
| **IAM Role (Task Execution)**                | `aws_iam_role` + `aws_iam_role_policy_attachment`   | Role that ECS uses to pull container images, push logs, etc. (uses AmazonECSTaskExecutionRolePolicy). |
| **IAM Role (Task)**                          | `aws_iam_role` + `aws_iam_policy` + `aws_iam_role_policy_attachment` | Application’s task role; here granted minimal privileges such as `vpc-lattice-svcs:Invoke` so tasks can call Lattice APIs【29†L457-L465】. |
| **IAM Role (Infrastructure)**                | `aws_iam_role` + `aws_iam_role_policy_attachment`   | ECS infrastructure role (trusted by ecs.amazonaws.com) with only VPC Lattice management policy (`AmazonECSInfrastructureRolePolicyForVpcLattice`)【24†L28-L31】【31†L1-L4】. |
| **Security Group (tasks)**                   | (user-provided)                                      | Allows inbound from VPC Lattice prefix list on container port; restricts other access. |
| **AWS CloudWatch Logs Permissions**          | (AWS-managed)                                        | ECS execution role must include permissions to create/put logs (handled by the managed policy). |
| **Output Values**                            | (module outputs)                                     | ARNs/IDs of the created Service, TaskDefinition, TargetGroup, Listener, Association, and IAM Roles. |

## Terraform Module Structure

```
ecs-lattice-module/
├── main.tf            # Resource definitions (ECS, VPC Lattice, IAM, etc.)
├── variables.tf       # Input variable definitions and descriptions
├── outputs.tf         # Output values (ARNs, IDs, etc.)
└── examples/
    └── example_usage.tf  # Example of how to call the module
```

**variables.tf** will define inputs such as `cluster_arn`, `service_name`, `container_image`, `container_port`, `cpu`, `memory`, `desired_count`, `subnets`, `security_group_ids`, `vpc_id`, `vpclattice_service_id` (or ARN), `service_network_id` (or ARN), `log_group_name`, optional `execution_role_arn`, `task_role_arn`, and `tags`. Unspecified values are exposed as variables for flexibility. 

**outputs.tf** will return the created ECS Service ARN, Task Definition ARN, Target Group ARN, Listener ID, Service-Network Association ID, and the ARNs of the IAM roles created. An example usage (in `examples/example_usage.tf`) shows passing these variables:

```hcl
module "ecs_lattice_service" {
  source               = "./ecs-lattice-module"
  cluster_arn          = aws_ecs_cluster.main.arn
  service_name         = "my-app"
  container_image      = "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest"
  container_port       = 8080
  container_port_name  = "http"            # must match task-definition port mapping name
  cpu                  = 256
  memory               = 512
  desired_count        = 3
  subnets              = [data.aws_subnet.subnet1.id, data.aws_subnet.subnet2.id]
  security_group_ids   = [aws_security_group.sg.id]
  vpc_id               = "vpc-0abc1234"
  vpclattice_service_id = "svc-0123456789abcdef0"
  service_network_id   = "sn-0abcdef1234567890"
  log_group_name       = "/ecs/my-app"
  tags = { Project = "MyApp", Environment = "prod" }
}
```

## Code Snippets

### ECS Task Definition and Logging

```hcl
resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_iam_role" "execution" {
  name = "${var.service_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${var.service_name}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Grant the task permission to call Lattice services (Invoke) – least-privilege for AWS_IAM auth
resource "aws_iam_policy" "task_invoke" {
  name   = "${var.service_name}-task-lattice-policy"
  path   = "/service-role/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "vpc-lattice-svcs:Invoke",
      Resource = [
        "${var.vpclattice_service_id}",         # service ARN or ID (without path suffix)
        "${var.vpclattice_service_id}/*"        # allow invoking any operation under the service
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_invoke_attach" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_invoke.arn
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = var.execution_role_arn != "" ? var.execution_role_arn : aws_iam_role.execution.arn
  task_role_arn      = var.task_role_arn != ""      ? var.task_role_arn      : aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.service_name
    image     = var.container_image
    cpu       = var.cpu
    memory    = var.memory
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
      name          = var.container_port_name  # e.g. "http"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = var.service_name
      }
    }
  }])
}

data "aws_region" "current" {}
```

In this snippet, the **execution role** trusts `ecs-tasks.amazonaws.com` and attaches the AWS-managed `AmazonECSTaskExecutionRolePolicy` (which includes CloudWatch Logs permissions). The **task role** also trusts ECS tasks, and we attach a custom policy allowing only the `vpc-lattice-svcs:Invoke` action on the specific Lattice service resource【29†L457-L465】. This enforces least privilege for the task to call Lattice (required when `AuthType=AWS_IAM`). If the service uses Lattice with IAM auth, tasks must use SigV4 to call it, so granting `Invoke` is essential.

### ECS Service with VPC Lattice Integration

```hcl
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets         = var.subnets
    security_groups = var.security_group_ids
    assign_public_ip = false
  }

  # VPC Lattice configuration block (requires AWS Provider ≥ v5.77.0)
  vpc_lattice_configurations {
    target_group_arn = aws_vpclattice_target_group.this.arn
    port_name        = var.container_port_name   # must match the portMapping name in task definition
    role_arn         = aws_iam_role.ecs_infra.arn  # infrastructure role for ECS
  }
}
```

Here, `vpc_lattice_configurations` attaches the ECS service to the Lattice target group. The `port_name` must match the `name` in the container’s port mapping (e.g. `"http"` in the example). The `role_arn` is the **ECS infrastructure role** that allows ECS to manage the Lattice target group. If not provided by the user, the module will create it (see below). Using Lattice in `awsvpc` mode means ECS will automatically register each task’s ENI private IP into the target group【18†L18-L24】【31†L1-L4】.

### VPC Lattice Target Group, Listener, and Association

```hcl
resource "aws_vpclattice_target_group" "this" {
  name = "${var.service_name}-tg"
  type = "IP"
  # The VPC ID is needed to create the target group
  vpc_identifier = var.vpc_id
  config {
    port             = var.container_port
    protocol         = "HTTPS"
    protocol_version = "HTTP1"
    ip_address_type  = "IPV4"
    health_check {
      enabled             = true
      protocol            = "HTTPS"
      path                = "/health"
      port                = var.container_port
      healthy_threshold   = 2
      unhealthy_threshold = 3
      matcher             = { http_code = "200" }
    }
  }
}

resource "aws_vpclattice_listener" "this" {
  service_identifier = var.vpclattice_service_id
  name               = var.service_name
  protocol           = "HTTP"
  port               = var.listener_port  # e.g. 80 or 443
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this.id
        weight                  = 100
      }
    }
  }
}

resource "aws_vpclattice_service_network_service_association" "this" {
  service_network_identifier = var.service_network_id
  service_identifier         = var.vpclattice_service_id
}
```

- **Target Group**: We create an IP‑type Lattice target group in the given VPC, listening on the container port (e.g. 8080) and using HTTPS health checks. In zero-trust setups, one would configure TLS on tasks and Lattice; here we assume HTTPS with a valid certificate on the Lattice side (via the `aws_vpclattice_service` configuration or custom domain). 
- **Listener**: This Lattice listener listens on a port (commonly 80 or 443) for the Lattice Service. Its default action forwards all traffic (weight 100) to the target group above.
- **Service-Network Association**: This associates the Lattice Service (identified by `vpclattice_service_id`) with the Service Network (`service_network_id`), making the service reachable to clients in that network.

The **flow of traffic** is thus: Clients in the Lattice Service Network call the Lattice Service’s DNS name (or via API Gateway, etc.) → the Lattice Listener receives the request → forwards to the target group → ECS tasks handle the request. The ECS tasks were automatically registered into the target group by the service’s VPC Lattice configuration.

### IAM Infrastructure Role for ECS

```hcl
resource "aws_iam_role" "ecs_infra" {
  name = "${var.service_name}-ecs-infra-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowECS",
      Effect    = "Allow",
      Principal = { Service = "ecs.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "infra_vpclattice" {
  role       = aws_iam_role.ecs_infra.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVpcLattice"
}
```

This **ECS infrastructure role** is assumed by the ECS service to manage AWS resources on our behalf【24†L28-L31】【31†L1-L4】. We attach only the AWS-managed policy `AmazonECSInfrastructureRolePolicyForVpcLattice`, which grants exactly the permissions ECS needs to *register/deregister task IPs* in the VPC Lattice target group. The trust policy allows only the ECS service (`ecs.amazonaws.com`) to assume it【24†L28-L31】【31†L1-L4】. This enforces least privilege: ECS cannot use this role to do anything outside VPC Lattice target group management.

## IAM Policy Examples (Least Privilege)

- **Task Execution Role** (AWS-managed): We attach **AmazonECSTaskExecutionRolePolicy**, which covers pulling from ECR, creating log groups/streams, etc. No custom changes needed (it is the least privilege Amazon-provided for this role).

- **Task Role Policy** (custom for Lattice): If the application code in tasks will call other VPC Lattice services, the task role needs:
  
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": [
        "arn:aws:vpc-lattice:REGION:ACCOUNT:service/svc-0123456789abcdef", 
        "arn:aws:vpc-lattice:REGION:ACCOUNT:service/svc-0123456789abcdef/*"
      ]
    }]
  }
  ```
  Replace with your region/account/service ARN. This grants the minimum action (`Invoke`) on the specific service resource【29†L457-L465】. **Note:** If `AuthType=AWS_IAM` is set on the Lattice service (highly recommended for zero-trust), then callers **must** use SigV4. This policy enables ECS tasks to do so. Without it, tasks would get “AccessDenied” when calling Lattice endpoints.

- **Lattice Listener Auth Policy** (resource-based): As an additional hardening step, one can define a VPC Lattice *auth policy* that restricts which IAM principals can call the service. For example, an auth policy JSON can specify that only a given IAM role or AWS account can access the service【26†L89-L97】. We would attach it to the service resource via `aws_vpclattice_auth_policy`. (Not shown here, but AWS docs recommend using Lattice auth policies for zero-trust).

Overall, all IAM policies are scoped to the smallest possible resources. The trust relationships only allow the correct AWS service to assume each role (e.g. `ecs.amazonaws.com` for the infra role)【24†L28-L31】【31†L1-L4】. 

## Variables (`variables.tf` Example)

```hcl
variable "cluster_arn" {
  description = "ARN of the existing ECS cluster to deploy the service into"
  type        = string
}

variable "service_name" {
  description = "Name for the ECS service and related resources"
  type        = string
}

variable "container_image" {
  description = "Docker image (with tag) for the container"
  type        = string
}

variable "container_port" {
  description = "Container port to expose and use for health checks"
  type        = number
}

variable "container_port_name" {
  description = "Name for the container port mapping (used in Lattice config)"
  type        = string
}

variable "cpu" {
  description = "CPU units for the task"
  type        = number
}

variable "memory" {
  description = "Memory (MiB) for the task"
  type        = number
}

variable "desired_count" {
  description = "Number of tasks to run in the service"
  type        = number
}

variable "subnets" {
  description = "List of subnet IDs for the ECS tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the ECS tasks"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for the Lattice target group"
  type        = string
}

variable "vpclattice_service_id" {
  description = "Identifier (ID or ARN) of the existing VPC Lattice Service to attach"
  type        = string
}

variable "service_network_id" {
  description = "Identifier (ID or ARN) of the VPC Lattice Service Network"
  type        = string
}

variable "listener_port" {
  description = "Port on which the Lattice Listener will accept traffic (e.g., 80 or 443)"
  type        = number
  default     = 80
}

variable "log_group_name" {
  description = "CloudWatch Log Group name for container logs"
  type        = string
}

variable "execution_role_arn" {
  description = "(Optional) Pre-existing ECS task execution role ARN"
  type        = string
  default     = ""
}

variable "task_role_arn" {
  description = "(Optional) Pre-existing ECS task role ARN"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
```

## Outputs (`outputs.tf` Example)

```hcl
output "ecs_service_arn" {
  description = "ARN of the created ECS Service"
  value       = aws_ecs_service.this.arn
}

output "task_definition_arn" {
  description = "ARN of the created ECS Task Definition"
  value       = aws_ecs_task_definition.this.arn
}

output "vpclattice_target_group_arn" {
  description = "ARN of the created VPC Lattice Target Group"
  value       = aws_vpclattice_target_group.this.arn
}

output "vpclattice_listener_id" {
  description = "ID of the created VPC Lattice Listener"
  value       = aws_vpclattice_listener.this.id
}

output "service_network_association_id" {
  description = "ID of the Service-Network association"
  value       = aws_vpclattice_service_network_service_association.this.id
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.task.arn
}

output "infrastructure_role_arn" {
  description = "ARN of the ECS infrastructure role (for VPC Lattice)"
  value       = aws_iam_role.ecs_infra.arn
}
```

## Architecture Diagram

Below is a simplified *flow* diagram (in Mermaid syntax) illustrating how the ECS service and VPC Lattice components interact:

```mermaid
graph LR
    subgraph "ECS Cluster"
      ECSService[ECS Service] -- registers tasks into --> TGT[VPC Lattice Target Group]
      ECSService --> ECS_Tasks[ECS Tasks (Fargate)]
    end
    VPCListener[VPC Lattice Listener] -->|Forwards to| TGT
    VPCService[VPC Lattice Service] --> VPCListener
    VPCService -->|attached to| ServiceNetwork[VPC Lattice Service Network]
    TGT -->|serves| ECS_Tasks
```

- **ECS Service** runs in Fargate mode. It automatically registers each task’s ENI IP into the **VPC Lattice Target Group**. 
- The **VPC Lattice Listener** (on the Lattice Service) forwards incoming requests to the target group.
- The **VPC Lattice Service** is attached to a **Service Network**, making it reachable to clients on that network.
- Traffic flows from clients (in the Service Network) → Lattice Service DNS → Listener → Target Group → ECS tasks.

This matches AWS’s design: “Amazon ECS automatically registers tasks to the VPC Lattice target group when tasks ... are launched”【18†L18-L24】, and health checks via Lattice keep tasks healthy.

## Security and Testing

**Zero-Trust IAM:** We have enforced least privilege:
- The **ECS infrastructure role** only has the VPC Lattice target-group policy【24†L28-L31】. Its trust is restricted to `ecs.amazonaws.com`. 
- The **task execution role** has only the official ECS managed policy.
- The **task role** has only `vpc-lattice-svcs:Invoke` on the specific service. 
- Consider additionally requiring `AuthType = AWS_IAM` on the Lattice Service and using Lattice *Auth Policies* so that even authenticated calls must come from allowed principals【26†L89-L97】.

**Network Controls:** Use strict Security Group rules:
- Only allow inbound from the **AWS-managed VPC Lattice prefix list** on the container port【54†L1-L4】. The prefix list name (e.g. `pl-...lattice-...`) is documented in AWS VPC Lattice docs. This ensures only Lattice traffic can hit the tasks. All other inbound (0.0.0.0/0) should be denied.
- Place tasks in **private subnets** with no public IP (unless required), so they are reachable only via Lattice.
- For outbound, you can restrict egress as needed (e.g., deny access to other AWS APIs except necessary ones).

**Testing/Validation Checklist:**

1. **Deployment Smoke Test:** Run the Terraform module and verify all resources are created without errors.
2. **Service Reachability:** After deployment, confirm that the VPC Lattice Service Network DNS name (or endpoint) successfully returns responses from the ECS tasks. This can be tested with `curl` from a client in the Service Network (e.g. an EC2 in the network) or using `aws vpc-lattice invoke-service`.
3. **Health Checks:** Check that the Lattice target group shows tasks as *healthy*. If tasks fail health checks, ECS should restart them. Monitor ECS events to ensure no failures.
4. **IAM Enforcement:** Attempt to call the service without valid AWS credentials (no SigV4) and verify it fails (if `AuthType=AWS_IAM`). Conversely, test that an authorized call (with a role permitted by an auth policy) succeeds.
5. **Least-Privilege Verification:** Use IAM Access Analyzer or AWS IAM Policy Simulator to verify no excess permissions. Also check CloudTrail to ensure actions are correctly logged under the intended roles.
6. **Logging:** Ensure ECS tasks are sending logs to CloudWatch (Log Group named). Check for errors or missing logs. 
7. **Network Filtering:** Confirm the security group only allows the VPC Lattice prefix list to connect. Try connecting to the task port from an unauthorized IP to ensure it is blocked.
8. **Failover Test:** Manually stop a task; ECS should start a new one and register it with the target group automatically. Verify continued connectivity during the transition.

By following these steps and reviewing AWS’s ECS and VPC Lattice documentation, the module and its usage can be thoroughly validated. The design adheres to AWS best practices: using managed policies for standard needs, requiring specific AWS roles to assume roles, and leveraging Lattice’s built-in security features【18†L50-L58】【24†L28-L31】.

**Sources:** AWS ECS and VPC Lattice official docs and examples【18†L18-L24】【22†L169-L172】【24†L28-L31】【29†L457-L465】【30†L161-L169】【54†L1-L4】 (Terraform AWS Provider documentation informed attribute usage). The module aligns with AWS architecture guidance for ECS + VPC Lattice【18†L18-L24】【31†L1-L4】.