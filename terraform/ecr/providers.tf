provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "tech-challenge"
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}
