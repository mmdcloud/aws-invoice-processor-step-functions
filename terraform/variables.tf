variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  sensitive   = true
}

variable "public_subnets" {
  type        = list(string)
  description = "Public Subnet CIDR values"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private Subnet CIDR values"
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
}