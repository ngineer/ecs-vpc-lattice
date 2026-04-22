output "ecs_service_arn" {
  value       = aws_ecs_service.this.arn
  description = "ARN of the ECS service."
}

output "ecs_service_name" {
  value       = aws_ecs_service.this.name
  description = "Name of the ECS service."
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.this.arn
  description = "ARN of the ECS task definition."
}

output "vpclattice_service_arn" {
  value       = aws_vpclattice_service.this.arn
  description = "ARN of the VPC Lattice service."
}

output "vpclattice_service_dns_entry" {
  value       = aws_vpclattice_service.this.dns_entry
  description = "DNS entry for the VPC Lattice service."
}

output "vpclattice_target_group_arn" {
  value       = aws_vpclattice_target_group.this.arn
  description = "ARN of the VPC Lattice target group."
}

output "vpclattice_listener_arn" {
  value       = aws_vpclattice_listener.this.arn
  description = "ARN of the VPC Lattice listener."
}

output "vpclattice_service_network_association_id" {
  value       = aws_vpclattice_service_network_service_association.this.id
  description = "ID of the service network association."
}
