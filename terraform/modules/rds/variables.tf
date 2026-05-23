variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "rds_instances" {
  description = "Map of RDS PostgreSQL instances to create (one per service)"
  type = map(object({
    db_name           = string
    instance_class    = string
    allocated_storage = number
  }))
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.8"
}

variable "master_username" {
  description = "Master username for all RDS instances"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the RDS instances"
  type        = list(string)
}
