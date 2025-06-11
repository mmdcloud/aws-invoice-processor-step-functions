# This Terraform configuration sets up an SNS topic for notifications.
module "notification_topic" {
  source     = "./modules/sns"
  topic_name = "notification-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
}

module "step_function" {
    source = "./modules/step-function"
    name = "InvoiceProcessingWorkflow"
    role_arn = ""
    definition = jsonencode({
      Comment = "A simple AWS Step Functions state machine that processes invoices",
      StartAt = "ProcessInvoice",
      States = {
        ProcessInvoice = {
          Type = "Task",
          Resource = "arn:aws:lambda:us-east-1:123456789012:function:ProcessInvoiceFunction",
          End = true
        }
      }
    })
}   

# S3 upload event rule to trigger a Step Function
module "s3_upload_event_rule" {
  source           = "./modules/eventbridge"
  rule_name        = "s3-upload-event-rule"
  rule_description = "Rule for S3 Upload Events"
  event_pattern = jsonencode({
    source = [
      "aws.s3"
    ]
    detail-type = [
      "PutObject",
      "CompleteMultipartUpload"
    ]
  })
  target_id  = "TriggerStepFunction"
  target_arn = module.step_function.arn
}