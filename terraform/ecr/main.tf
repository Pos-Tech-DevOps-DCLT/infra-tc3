module "ecr" {
  source = "../modules/ecr"

  name_prefix           = "tech-challenge-prod"
  repository_names      = var.repositories
  image_retention_count = var.image_retention_count
}
