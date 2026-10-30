variable "name" {
  type        = string
  description = "The name of the state machine"
}

variable "role_arn" {
  type        = string
  description = "The Amazon Resource Name (ARN) of the IAM role to use for this state machine"
}

variable "definition" {
  type        = string
  description = "The Amazon States Language definition of the state machine"
}

variable "tracing_enabled" {
  type        = bool
  default     = true
  description = "Defines whether AWS X-Ray tracing is enabled"
}

variable "log_level" {
  type        = string
  default     = "ALL"
  description = "Defines what execution history events will be logged (OFF, ALL, ERROR, FATAL)"
}

variable "log_retention_in_days" {
  type        = number
  default     = 30
  description = "CloudWatch log retention in days for Step Functions execution history"
}
