variable "topic_name" {
  type        = string
  description = "The name of the SNS topic"
}

variable "subscriptions" {
  type = list(object({
    protocol = string
    endpoint = string
  }))
  default     = []
  description = "List of subscriptions for the topic"
}

variable "kms_master_key_id" {
  type        = string
  default     = "alias/aws/sns"
  description = "The ID of an AWS-managed customer master key (CMK) for Amazon SNS or a custom CMK"
}
