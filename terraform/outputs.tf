# outputs.tf
output "invoices_bucket_name" {
  description = "Name of the invoices S3 bucket"
  value       = module.invoices_bucket.bucket
}

output "step_function_arn" {
  description = "ARN of the Step Function"
  value       = module.step_function.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.invoice_records_dynamodb.name
}