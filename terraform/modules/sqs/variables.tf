variable "queue_name" {
  type        = string
  description = "Name of the SQS queue"
}

variable "delay_seconds" {
  type        = number
  default     = 0
  description = "The time in seconds that the delivery of all messages in the queue will be delayed"
}

variable "max_message_size" {
  type        = number
  default     = 262144
  description = "The limit of how many bytes a message can contain"
}

variable "message_retention_seconds" {
  type        = number
  default     = 345600
  description = "The number of seconds Amazon SQS retains a message"
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 180
  description = "The visibility timeout for the queue in seconds"
}

variable "receive_wait_time_seconds" {
  type        = number
  default     = 20
  description = "The time for which a ReceiveMessage call will wait for a message to arrive"
}

variable "policy" {
  type        = string
  default     = null
  description = "The JSON policy for the SQS queue"
}

variable "redrive_policy" {
  type        = string
  default     = null
  description = "The JSON policy for the SQS redrive policy"
}

variable "redrive_allow_policy" {
  type        = string
  default     = null
  description = "The JSON policy for the SQS redrive allow policy"
}

variable "sqs_managed_sse_enabled" {
  type        = bool
  default     = true
  description = "Boolean to enable server-side encryption (SSE) of message content with SQS-owned encryption keys"
}

variable "kms_master_key_id" {
  type        = string
  default     = null
  description = "The ID of an AWS-managed customer master key (CMK) for Amazon SQS or a custom CMK"
}
