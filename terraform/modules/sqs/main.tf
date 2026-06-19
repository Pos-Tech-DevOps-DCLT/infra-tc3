locals {
  queue_name = "${var.name_prefix}-${var.queue_name}"
  dlq_name   = "${var.name_prefix}-${var.queue_name}-dlq"
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = local.dlq_name
  message_retention_seconds = 1209600 # 14 days max for DLQ
  sqs_managed_sse_enabled   = true

  tags = {
    Name = local.dlq_name
  }
}

# Main Queue
resource "aws_sqs_queue" "main" {
  name                       = local.queue_name
  visibility_timeout_seconds = var.visibility_timeout
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  # Enable long polling (20 seconds reduces empty responses and cost)
  receive_wait_time_seconds = 20

  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = {
    Name = local.queue_name
  }
}

# Queue Policy - allows EKS nodes IAM role to send/receive messages
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSendReceive"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "dlq" {
  count     = var.enable_dlq ? 1 : 0
  queue_url = aws_sqs_queue.dlq[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowManage"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.dlq[0].arn
      }
    ]
  })
}

# CloudWatch Alarms for DLQ monitoring
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.enable_dlq ? 1 : 0

  alarm_name          = "${local.dlq_name}-messages-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when messages appear in the Dead Letter Queue"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[0].name
  }

  tags = {
    Name = "${local.dlq_name}-alarm"
  }
}
