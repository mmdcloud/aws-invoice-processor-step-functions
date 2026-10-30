variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "A boolean that indicates all objects should be deleted from the bucket so that the bucket can be destroyed without error"
}

variable "versioning_enabled" {
  type        = string
  default     = "Enabled"
  description = "The versioning state of the bucket"
}

variable "objects" {
  type = list(object({
    source = string
    key    = string
  }))
  default     = []
  description = "List of objects to upload to the bucket"
}

variable "cors" {
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    max_age_seconds = number
  }))
  default     = []
  description = "CORS rules for the bucket"
}

variable "bucket_policy" {
  type        = string
  default     = ""
  description = "Bucket policy JSON string"
}

variable "bucket_notification" {
  type = object({
    queue = list(object({
      queue_arn = string
      events    = list(string)
    }))
    lambda_function = list(object({
      lambda_function_arn = string
      events              = list(string)
    }))
  })
  default = {
    queue           = []
    lambda_function = []
  }
  description = "Notification configurations for SQS queues and Lambda functions"
}

variable "block_public_acls" {
  type        = bool
  default     = true
  description = "Whether Amazon S3 should block public ACLs for this bucket"
}

variable "block_public_policy" {
  type        = bool
  default     = true
  description = "Whether Amazon S3 should block public bucket policies for this bucket"
}

variable "ignore_public_acls" {
  type        = bool
  default     = true
  description = "Whether Amazon S3 should ignore public ACLs for this bucket"
}

variable "restrict_public_buckets" {
  type        = bool
  default     = true
  description = "Whether Amazon S3 should restrict public bucket policies for this bucket"
}

variable "sse_algorithm" {
  type        = string
  default     = "AES256"
  description = "Server-side encryption algorithm to use"
}

variable "kms_master_key_id" {
  type        = string
  default     = null
  description = "The AWS KMS master key ID used for the SSE-KMS encryption"
}

variable "enforce_tls" {
  type        = bool
  default     = true
  description = "Whether to deny HTTP/unencrypted TLS requests to this bucket"
}
