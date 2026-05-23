variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
}

variable "image_retention_count" {
  description = "Number of tagged images to retain per repository"
  type        = number
  default     = 10
}
