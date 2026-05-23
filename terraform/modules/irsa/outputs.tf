output "keda_role_arn" {
  description = "ARN of the IRSA role for KEDA operator"
  value       = aws_iam_role.keda.arn
}

output "evaluation_service_role_arn" {
  description = "ARN of the IRSA role for evaluation-service"
  value       = aws_iam_role.evaluation_service.arn
}

output "analytics_service_role_arn" {
  description = "ARN of the IRSA role for analytics-service"
  value       = aws_iam_role.analytics_service.arn
}
