variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster and nodes"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for the EKS worker nodes"
  type        = string
}
