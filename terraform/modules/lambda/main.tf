# Dedicated CloudWatch Log Group with retention to avoid unmanaged indefinite retention
resource "aws_cloudwatch_log_group" "function_log_group" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
}

# Lambda Function
resource "aws_lambda_function" "function" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size
  s3_bucket     = var.s3_bucket
  s3_key        = var.s3_key

  tracing_config {
    mode = var.tracing_mode
  }

  dynamic "environment" {
    for_each = length(var.env_variables) > 0 ? [1] : []
    content {
      variables = var.env_variables
    }
  }

  depends_on = [aws_cloudwatch_log_group.function_log_group]
}

# Granting permissions for lambda
resource "aws_lambda_permission" "lambda_function_permission" {
  count         = length(var.permissions)
  statement_id  = var.permissions[count.index].statement_id
  function_name = aws_lambda_function.function.arn
  action        = var.permissions[count.index].action
  principal     = var.permissions[count.index].principal
  source_arn    = var.permissions[count.index].source_arn
}
