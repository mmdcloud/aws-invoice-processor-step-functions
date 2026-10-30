variable "name" {
  type        = string
  description = "Name of the DynamoDB table"
}

variable "billing_mode" {
  type        = string
  default     = "PAY_PER_REQUEST"
  description = "Controls how you are charged for read and write throughput and how you manage capacity"
}

variable "read_capacity" {
  type        = number
  default     = null
  description = "The number of read units for this table"
}

variable "write_capacity" {
  type        = number
  default     = null
  description = "The number of write units for this table"
}

variable "hash_key" {
  type        = string
  description = "The attribute to use as the hash key"
}

variable "range_key" {
  type        = string
  default     = null
  description = "The attribute to use as the range key"
}

variable "attributes" {
  type = list(object({
    name = string
    type = string
  }))
  description = "List of nested attribute definitions"
}

variable "ttl_attribute_name" {
  type        = string
  default     = "TimeToExist"
  description = "The name of the TTL attribute"
}

variable "ttl_attribute_enabled" {
  type        = bool
  default     = true
  description = "Indicates whether TTL is enabled"
}

variable "point_in_time_recovery" {
  type        = bool
  default     = true
  description = "Enable DynamoDB Point-in-Time Recovery (PITR)"
}

variable "server_side_encryption" {
  type        = bool
  default     = true
  description = "Enable DynamoDB Server-Side Encryption (SSE)"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "The ARN of the CMK that should be used for the AWS KMS encryption"
}

variable "deletion_protection_enabled" {
  type        = bool
  default     = false
  description = "Enables deletion protection for table"
}
