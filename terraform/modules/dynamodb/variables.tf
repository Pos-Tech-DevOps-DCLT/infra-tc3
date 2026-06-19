variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "table_name" {
  description = "Name suffix for the DynamoDB table"
  type        = string
}

variable "billing_mode" {
  description = "DynamoDB billing mode: PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "hash_key" {
  description = "Attribute name used as the hash (partition) key"
  type        = string
}

variable "range_key" {
  description = "Attribute name used as the range (sort) key. Leave empty to omit."
  type        = string
  default     = ""
}

variable "read_capacity" {
  description = "Read capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Write capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}
