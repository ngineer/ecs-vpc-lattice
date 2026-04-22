output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "ecs_service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.this.id
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "vpclattice_target_group_arn" {
  description = "ARN of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.this.arn
}

output "vpclattice_target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.this.id
}

output "vpclattice_service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.this.arn
}

output "vpclattice_service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.this.id
}

output "vpclattice_service_dns_name" {
  description = "DNS name of the VPC Lattice service"
  value       = aws_vpclattice_service.this.dns_entry[0].domain_name
}

output "vpclattice_listener_id" {
  description = "ID of the VPC Lattice listener"
  value       = aws_vpclattice_listener.this.id
}

output "vpclattice_service_network_association_id" {
  description = "ID of the service network association"
  value       = aws_vpclattice_service_network_service_association.this.id
}