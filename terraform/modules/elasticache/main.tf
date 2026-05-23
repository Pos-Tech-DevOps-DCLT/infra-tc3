resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.name_prefix}-redis-subnet-group"
  description = "Subnet group for ElastiCache Redis"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-redis-subnet-group"
  }
}

resource "aws_elasticache_parameter_group" "redis" {
  name        = "${var.name_prefix}-redis-params"
  family      = "redis${split(".", var.engine_version)[0]}"
  description = "Custom parameter group for Redis"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis replication group for ${var.name_prefix}"

  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes
  engine_version       = var.engine_version
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = var.security_group_ids

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result

  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false
  multi_az_enabled           = var.num_cache_nodes > 1 ? true : false

  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_window          = "03:00-04:00"
  snapshot_retention_limit = 7

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "engine-log"
  }

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.name_prefix}/elasticache/redis"
  description             = "Auth token for ElastiCache Redis"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    auth_token          = random_password.redis_auth.result
    primary_endpoint    = aws_elasticache_replication_group.main.primary_endpoint_address
    reader_endpoint     = aws_elasticache_replication_group.main.reader_endpoint_address
    port                = 6379
  })
}

resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "/aws/elasticache/${var.name_prefix}-redis/slow-log"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "redis_engine" {
  name              = "/aws/elasticache/${var.name_prefix}-redis/engine-log"
  retention_in_days = 7
}
