## VPC Auth Policy

## Approach 1: Enhanced Module with IAM Role List Variable

### Updated `variables.tf` (add these)

```hcl
variable "lattice_auth_allowed_principals" {
  description = "List of IAM principals (roles, users, accounts) allowed to invoke the service"
  type = list(object({
    type = string # "AWS", "Service", "Federated", "CanonicalUser"
    identifiers = list(string)
  }))
  default = []
}

variable "lattice_auth_allowed_organizations" {
  description = "List of AWS Organizations IDs to allow access from"
  type        = list(string)
  default     = []
}

variable "lattice_auth_additional_statements" {
  description = "Additional IAM policy statements to merge with the generated policy"
  type        = any
  default     = []
}
```

### Add Policy Generation Helper in `main.tf`

```hcl
# ------------------------------------------------------------------------------
# Generate Zero‑Trust Auth Policy from principal list
# ------------------------------------------------------------------------------
locals {
  # Generate policy if using the simplified principal list approach
  generated_auth_policy = var.lattice_auth_type == "AWS_IAM" && length(var.lattice_auth_allowed_principals) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Principal = {
            for principal in var.lattice_auth_allowed_principals : principal.type => principal.identifiers
          }
          Action   = "vpc-lattice-svcs:Invoke"
          Resource = "*"
        }
      ],
      length(var.lattice_auth_allowed_organizations) > 0 ? [
        {
          Effect = "Allow"
          Principal = {
            AWS = "*"
          }
          Action = "vpc-lattice-svcs:Invoke"
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:PrincipalOrgID" : var.lattice_auth_allowed_organizations
            }
          }
        }
      ] : [],
      var.lattice_auth_additional_statements
    )
  }) : null

  # Use explicit policy if provided, otherwise use generated one
  final_auth_policy = var.lattice_auth_policy != null ? var.lattice_auth_policy : local.generated_auth_policy
}

# ------------------------------------------------------------------------------
# VPC Lattice Auth Policy (IAM‑based zero trust)
# ------------------------------------------------------------------------------
resource "aws_vpclattice_auth_policy" "this" {
  count = var.lattice_auth_type == "AWS_IAM" && local.final_auth_policy != null ? 1 : 0

  resource_identifier = aws_vpclattice_service.this.arn
  policy              = local.final_auth_policy
}
```

---

## Approach 2: Separate IAM Role List Variable with Validation

### Alternative `variables.tf` (simpler version)

```hcl
variable "lattice_allowed_role_arns" {
  description = "List of IAM role ARNs allowed to invoke the VPC Lattice service"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.lattice_allowed_role_arns : can(regex("^arn:aws:iam::[0-9]+:role/", arn))
    ])
    error_message = "All values must be valid IAM role ARNs."
  }
}

variable "lattice_allowed_account_ids" {
  description = "List of AWS account IDs to allow access from any principal"
  type        = list(string)
  default     = []
}

variable "lattice_require_mfa" {
  description = "Require MFA for VPC Lattice service invocation"
  type        = bool
  default     = false
}
```

### Policy Generation in `main.tf`

```hcl
locals {
  # Build principal map from role ARNs
  role_principals = var.lattice_auth_type == "AWS_IAM" && length(var.lattice_allowed_role_arns) > 0 ? {
    AWS = var.lattice_allowed_role_arns
  } : null

  # Build account-wide principal condition
  account_condition = var.lattice_auth_type == "AWS_IAM" && length(var.lattice_allowed_account_ids) > 0 ? {
    StringEquals = {
      "aws:PrincipalAccount" : var.lattice_allowed_account_ids
    }
  } : null

  # Build MFA condition if required
  mfa_condition = var.lattice_require_mfa ? {
    Bool = {
      "aws:MultiFactorAuthPresent" : true
    }
  } : null

  # Merge conditions
  combined_conditions = merge(
    local.account_condition != null ? local.account_condition : {},
    local.mfa_condition != null ? local.mfa_condition : {}
  )

  # Generate the policy
  generated_policy = var.lattice_auth_type == "AWS_IAM" && (length(var.lattice_allowed_role_arns) > 0 || length(var.lattice_allowed_account_ids) > 0) ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = local.role_principals != null ? local.role_principals : { AWS = "*" }
        Action    = "vpc-lattice-svcs:Invoke"
        Resource  = "*"
        Condition = length(local.combined_conditions) > 0 ? local.combined_conditions : null
      }
    ]
  }) : null

  final_auth_policy = var.lattice_auth_policy != null ? var.lattice_auth_policy : local.generated_policy
}
```

---

## Usage Examples

### Example 1: Allow Specific IAM Roles

```hcl
module "my_app" {
  source = "./ecs-lattice-module"

  # ... other configuration ...

  lattice_auth_type = "AWS_IAM"
  
  # Allow multiple specific roles
  lattice_allowed_role_arns = [
    "arn:aws:iam::123456789012:role/ApplicationRole1",
    "arn:aws:iam::123456789012:role/ApplicationRole2",
    "arn:aws:iam::123456789012:role/MonitoringRole",
    "arn:aws:iam::098765432109:role/CrossAccountRole"
  ]
}
```

### Example 2: Allow Roles + Require MFA

```hcl
module "my_app" {
  source = "./ecs-lattice-module"

  # ... other configuration ...

  lattice_auth_type = "AWS_IAM"
  
  lattice_allowed_role_arns = [
    "arn:aws:iam::123456789012:role/AdminRole",
    "arn:aws:iam::123456789012:role/DeveloperRole"
  ]
  
  lattice_require_mfa = true
}
```

### Example 3: Allow Specific Accounts + Organization

```hcl
module "my_app" {
  source = "./ecs-lattice-module"

  # ... other configuration ...

  lattice_auth_type = "AWS_IAM"
  
  # Allow specific accounts (any principal within them)
  lattice_allowed_account_ids = [
    "123456789012",
    "098765432109"
  ]
  
  # Also allow entire AWS Organization
  lattice_allowed_organizations = ["o-abc123def456"]
}
```

### Example 4: Complex Principal List (Multiple Types)

```hcl
module "my_app" {
  source = "./ecs-lattice-module"

  # ... other configuration ...

  lattice_auth_type = "AWS_IAM"
  
  lattice_auth_allowed_principals = [
    {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::123456789012:role/Role1",
        "arn:aws:iam::123456789012:role/Role2",
        "123456789012"  # account ID for any principal
      ]
    },
    {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    },
    {
      type = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }
  ]
  
  lattice_require_mfa = true
}
```

### Example 5: Using Explicit Custom Policy (for complex scenarios)

```hcl
module "my_app" {
  source = "./ecs-lattice-module"

  # ... other configuration ...

  lattice_auth_type = "AWS_IAM"
  
  # Explicit custom policy for advanced scenarios
  lattice_auth_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::123456789012:role/RoleA",
            "arn:aws:iam::123456789012:role/RoleB"
          ]
        }
        Action   = "vpc-lattice-svcs:Invoke"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/Environment": "production"
          }
          Bool = {
            "aws:MultiFactorAuthPresent": "true"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:role/RoleC"
        }
        Action   = "vpc-lattice-svcs:Invoke"
        Resource = "*"
        Condition = {
          IpAddress = {
            "aws:SourceIp": "10.0.0.0/8"
          }
        }
      }
    ]
  })
}
```

---

## Complete Example with All Features

```hcl
module "zero_trust_app" {
  source = "./ecs-lattice-module"

  # ECS Configuration
  cluster_name         = "production-cluster"
  service_name         = "payment-service"
  task_family          = "payment-processor"
  container_definitions = jsonencode([
    {
      name  = "payment"
      image = "payment-processor:latest"
      portMappings = [{
        containerPort = 8080
        hostPort      = 0
      }]
    }
  ])
  execution_role_arn = "arn:aws:iam::123456789012:role/ecsExecution"
  network_mode       = "bridge"
  desired_count      = 3

  # VPC Lattice Configuration
  vpc_lattice_service_network_id = "sn-1234567890abcdef0"
  lattice_service_name           = "payment-service"
  target_group_name              = "payment-tg"
  target_group_port              = 8080
  target_group_vpc_id            = "vpc-1234567890abcdef0"

  # Zero Trust: Allow specific roles only
  lattice_auth_type          = "AWS_IAM"
  lattice_allowed_role_arns  = [
    "arn:aws:iam::123456789012:role/FrontendAppRole",
    "arn:aws:iam::123456789012:role/AdminRole",
    "arn:aws:iam::123456789012:role/APIGatewayRole"
  ]
  lattice_require_mfa        = true
  
  # Additional conditions via explicit policy statements
  lattice_auth_additional_statements = [
    {
      Effect = "Deny"
      Principal = "*"
      Action = "vpc-lattice-svcs:Invoke"
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:SourceVpc": "vpc-1234567890abcdef0"
        }
      }
    }
  ]

  tags = {
    Environment = "production"
    Service     = "payments"
    Compliance  = "pci-dss"
  }
}
```

This approach gives you maximum flexibility while maintaining a clean, reusable module interface for zero‑trust authentication with VPC Lattice.
