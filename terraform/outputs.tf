# outputs.tf
output "invoices_bucket_name" {
  description = "Name of the invoices S3 bucket"
  value       = module.invoices_bucket.bucket
}

output "invoices_bucket_arn" {
  description = "ARN of the invoices S3 bucket"
  value       = module.invoices_bucket.arn
}

output "document_event_queue_url" {
  description = "URL of the primary SQS document event queue"
  value       = module.document_event_queue.url
}

output "document_event_queue_arn" {
  description = "ARN of the primary SQS document event queue"
  value       = module.document_event_queue.arn
}

output "document_event_dlq_url" {
  description = "URL of the SQS document event dead-letter queue"
  value       = module.document_event_dlq.url
}

output "document_event_dlq_arn" {
  description = "ARN of the SQS document event dead-letter queue"
  value       = module.document_event_dlq.arn
}

output "step_function_arn" {
  description = "ARN of the Step Function state machine"
  value       = module.step_function.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.invoice_records_dynamodb.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = module.invoice_records_dynamodb.arn
}

output "invalid_invoice_error_topic_arn" {
  description = "ARN of SNS topic for invalid invoice error notifications"
  value       = module.invalid_invoice_error_topic.topic_arn
}

output "data_storage_failure_topic_arn" {
  description = "ARN of SNS topic for data storage failure notifications"
  value       = module.data_storage_failure_topic.topic_arn
}
