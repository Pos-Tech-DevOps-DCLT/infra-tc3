resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-rds-subnet-group"
  description = "Subnet group for RDS instances"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-rds-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.name_prefix}-postgres-params"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "Custom parameter group for PostgreSQL"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "rds" {
  for_each = var.rds_instances

  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# recovery_window_in_days = 0 allows immediate deletion on terraform destroy,
# preventing "secret scheduled for deletion" errors on the next apply.
resource "aws_secretsmanager_secret" "rds" {
  for_each = var.rds_instances

  name                    = "${var.name_prefix}/rds/${each.key}"
  description             = "Credentials for RDS ${each.key} instance"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds" {
  for_each = var.rds_instances

  secret_id = aws_secretsmanager_secret.rds[each.key].id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.rds[each.key].result
    host     = aws_db_instance.main[each.key].address
    port     = aws_db_instance.main[each.key].port
    dbname   = each.value.db_name
    engine   = "postgres"
  })
}

resource "aws_db_instance" "main" {
  for_each = var.rds_instances

  identifier        = "${var.name_prefix}-${each.key}"
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = each.value.instance_class
  allocated_storage = each.value.allocated_storage
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = each.value.db_name
  username = var.master_username
  password = random_password.rds[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.postgres.name

  multi_az            = var.multi_az
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true
  copy_tags_to_snapshot = true

  backup_retention_period = 0
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.name_prefix}-${each.key}-rds"
  }
}
