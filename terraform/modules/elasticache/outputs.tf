output "primary_endpoint" {
  description = "Primary endpoint address for the Redis replication group"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
}

output "reader_endpoint" {
  description = "Reader endpoint address for the Redis replication group"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
  sensitive   = true
}

output "port" {
  description = "Port number for the Redis cluster"
  value       = 6379
}

output "replication_group_id" {
  description = "ID of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.main.id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret for Redis auth token"
  value       = aws_secretsmanager_secret.redis.arn
}
