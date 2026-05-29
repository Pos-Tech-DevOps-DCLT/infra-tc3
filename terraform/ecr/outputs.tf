output "repository_urls" {
  description = "ECR repository URLs — use these in your Docker push commands and k8s manifests"
  value       = module.ecr.repository_urls
}

output "registry" {
  description = "ECR registry hostname (account-id.dkr.ecr.region.amazonaws.com)"
  value       = split("/", values(module.ecr.repository_urls)[0])[0]
}
