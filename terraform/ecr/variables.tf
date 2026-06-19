variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "repositories" {
  description = "ECR repository names — one per microservice"
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service"
  ]
}

variable "image_retention_count" {
  description = "Number of tagged images to keep per repository"
  type        = number
  default     = 10
}
