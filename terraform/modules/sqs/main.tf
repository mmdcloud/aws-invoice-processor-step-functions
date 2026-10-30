# SQS queue
resource "aws_sqs_queue" "queue" {
  name                       = var.queue_name
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  policy                     = var.policy != "" && var.policy != null ? var.policy : null
  redrive_policy             = var.redrive_policy
  redrive_allow_policy       = var.redrive_allow_policy
  sqs_managed_sse_enabled    = var.kms_master_key_id == null ? var.sqs_managed_sse_enabled : null
  kms_master_key_id          = var.kms_master_key_id
}
