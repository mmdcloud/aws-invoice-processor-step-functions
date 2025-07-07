variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default = ""
  sensitive   = true
}