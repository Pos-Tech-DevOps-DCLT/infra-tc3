variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "node_type" {
  description = "Instance type for ElastiCache nodes"
  type        = string
}

variable "num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ElastiCache subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for ElastiCache"
  type        = list(string)
}
