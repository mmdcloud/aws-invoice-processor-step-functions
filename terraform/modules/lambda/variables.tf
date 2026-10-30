variable "function_name" {
  type        = string
  description = "A unique name for your Lambda Function"
}

variable "role_arn" {
  type        = string
  description = "IAM role attached to the Lambda Function"
}

variable "handler" {
  type        = string
  description = "Function entrypoint in your code"
}

variable "runtime" {
  type        = string
  default     = "python3.12"
  description = "Identifier of the function's runtime"
}

variable "s3_bucket" {
  type        = string
  description = "The S3 bucket location where the function's deployment package is stored"
}

variable "s3_key" {
  type        = string
  description = "The S3 key of an object containing the function's deployment package"
}

variable "timeout" {
  type        = number
  default     = 60
  description = "Amount of time your Lambda Function has to run in seconds"
}

variable "memory_size" {
  type        = number
  default     = 256
  description = "Amount of memory in MB your Lambda Function can use at runtime"
}

variable "tracing_mode" {
  type        = string
  default     = "Active"
  description = "Tracing mode (PassThrough or Active) for AWS X-Ray"
}

variable "log_retention_in_days" {
  type        = number
  default     = 30
  description = "Specifies the number of days you want to retain log events in the specified log group"
}

variable "env_variables" {
  type        = map(string)
  default     = {}
  description = "Map of environment variables that are accessible from the function code during execution"
}

variable "permissions" {
  type = list(object({
    statement_id = string
    action       = string
    principal    = string
    source_arn   = string
  }))
  default     = []
  description = "List of permissions to attach to the Lambda function"
}
