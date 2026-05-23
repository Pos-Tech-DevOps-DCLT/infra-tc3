output "queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}
