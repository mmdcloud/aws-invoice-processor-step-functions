# CloudWatch log group for Step Functions execution logs
resource "aws_cloudwatch_log_group" "sfn_log_group" {
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_in_days
}

resource "aws_sfn_state_machine" "state_machine" {
  name       = var.name
  role_arn   = var.role_arn
  definition = var.definition

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
    include_execution_data = true
    level                  = var.log_level
  }
}
