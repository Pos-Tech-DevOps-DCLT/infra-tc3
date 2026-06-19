locals {
  table_name    = "${var.name_prefix}-${var.table_name}"
  has_range_key = var.range_key != ""
}

resource "aws_dynamodb_table" "main" {
  name         = local.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = local.has_range_key ? var.range_key : null

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  attribute {
    name = var.hash_key
    type = "S"
  }

  dynamic "attribute" {
    for_each = local.has_range_key ? [var.range_key] : []
    content {
      name = attribute.value
      type = "S"
    }
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = local.table_name
  }
}

# Auto Scaling for PROVISIONED mode
resource "aws_appautoscaling_target" "dynamodb_table_read" {
  count = var.billing_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = 100
  min_capacity       = var.read_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  count = var.billing_mode == "PROVISIONED" ? 1 : 0

  name               = "${local.table_name}-read-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write" {
  count = var.billing_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = 100
  min_capacity       = var.write_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  count = var.billing_mode == "PROVISIONED" ? 1 : 0

  name               = "${local.table_name}-write-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70
  }
}
