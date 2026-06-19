variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "queue_name" {
  description = "Name suffix for the SQS queue"
  type        = string
}

variable "visibility_timeout" {
  description = "Visibility timeout in seconds"
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Message retention period in seconds (60 to 1209600)"
  type        = number
  default     = 86400
}

variable "enable_dlq" {
  description = "Enable a Dead Letter Queue"
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Times a message can be received before being sent to the DLQ"
  type        = number
  default     = 3
}
