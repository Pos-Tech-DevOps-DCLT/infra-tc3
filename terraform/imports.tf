import {
  to = module.ecr.aws_ecr_repository.repos["analytics-service"]
  id = "tech-challenge-prod/analytics-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["auth-service"]
  id = "tech-challenge-prod/auth-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["evaluation-service"]
  id = "tech-challenge-prod/evaluation-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["flag-service"]
  id = "tech-challenge-prod/flag-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["targeting-service"]
  id = "tech-challenge-prod/targeting-service"
}
