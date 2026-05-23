output "endpoints" {
  description = "Map of RDS instance key to endpoint (host:port)"
  value       = { for k, v in aws_db_instance.main : k => v.endpoint }
  sensitive   = true
}

output "addresses" {
  description = "Map of RDS instance key to hostname"
  value       = { for k, v in aws_db_instance.main : k => v.address }
  sensitive   = true
}

output "ports" {
  description = "Map of RDS instance key to port"
  value       = { for k, v in aws_db_instance.main : k => v.port }
}

output "secret_arns" {
  description = "Map of RDS instance key to Secrets Manager ARN"
  value       = { for k, v in aws_secretsmanager_secret.rds : k => v.arn }
}

output "subnet_group_name" {
  description = "Name of the RDS DB subnet group"
  value       = aws_db_subnet_group.main.name
}
