# -----------------------------------------------------------------------------------------
# SNS Configuration
# -----------------------------------------------------------------------------------------

module "invalid_invoice_error_topic" {
  source     = "./modules/sns"
  topic_name = "invalid-invoice-error-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
}

module "data_storage_failure_topic" {
  source     = "./modules/sns"
  topic_name = "data-storage-failure-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------

module "invoices_bucket" {
  source             = "./modules/s3"
  bucket_name        = "invoicesbucketmadmax"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
}

module "extract_table_data_function_code" {
  source      = "./modules/s3"
  bucket_name = "extracttabledatamadmax"
  objects = [
    {
      key    = "extract_table_data.zip"
      source = "./files/extract_table_data.zip"
    }
  ]
  bucket_policy = ""
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
}

module "table_sanity_check_function_code" {
  source      = "./modules/s3"
  bucket_name = "tablesanitycheckmadmax"
  objects = [
    {
      key    = "table_sanity_check.zip"
      source = "./files/table_sanity_check.zip"
    }
  ]
  bucket_policy = ""
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
}

# -----------------------------------------------------------------------------------------
# Step Function Configuration
# -----------------------------------------------------------------------------------------

module "step_function" {
  source     = "./modules/step-function"
  name       = "InvoiceProcessingWorkflow"
  role_arn   = ""
  definition = <<EOF
      {
        "Comment": "Invoice processing workflow",
        "StartAt": "CompleteMultipartUpload",
        "States": {          
          "Validate Table Information": {
            "Type": "Task",
            "Resource": "${module.table_sanity_check_function.arn}",
            "Output": "{% $states.result.Payload %}",
            "Arguments": {
              "FunctionName": "",
              "Payload": "{% $states.input %}"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException",
                  "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2,
                "JitterStrategy": "FULL"
              }
            ],
            "Next": "If validated"
          },
          "If validated": {
            "Type": "Choice",
            "Choices": [
              {
                "Next": "Error : Invalid invoice"
              }
            ],
            "Default": "Store data into Redshift"
          },
          "Error : Invalid invoice": {
            "Type": "Task",
            "Resource": "${module.invalid_invoice_error_topic.topic_arn}",
            "Arguments": {
              "Message": "{% $states.input %}"
            },
            "Next": "Fail"
          },
          "Fail": {
            "Type": "Fail"
          },
          "Store data into Redshift": {
            "Type": "Task",
            "Resource": "${module.extract_table_data_function.arn}",
            "Output": "{% $states.result.Payload %}",
            "Arguments": {
              "FunctionName": "",
              "Payload": "{% $states.input %}"
            },
            "Retry": [
              {
                "ErrorEquals": [
                  "Lambda.ServiceException",
                  "Lambda.AWSLambdaException",
                  "Lambda.SdkClientException",
                  "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2,
                "JitterStrategy": "FULL"
              }
            ],
            "Next": "If data stored successfully"
          },
          "If data stored successfully": {
            "Type": "Choice",
            "Choices": [
              {
                "Next": "Error: Failure while storing data"
              }
            ],
            "Default": "Success"
          },
          "Error: Failure while storing data": {
            "Type": "Task",
            "Resource": "${module.data_storage_failure_topic.topic_arn}",
            "Arguments": {
              "Message": "{% $states.input %}"
            },
            "Next": "Fail"
          },
          "Success": {
            "Type": "Succeed"
          }
        },
        "QueryLanguage": "JSONata"
      }
    EOF 
  # jsonencode({
  #   Comment = "A simple AWS Step Functions state machine that processes invoices",
  #   StartAt = "ProcessInvoice",
  #   States = {
  #     ProcessInvoice = {
  #       Type = "Task",
  #       Resource = "arn:aws:lambda:us-east-1:123456789012:function:ProcessInvoiceFunction",
  #       End = true
  #     }
  #   }
  # })
}

# -----------------------------------------------------------------------------------------
# Eventbridge Configuration
# -----------------------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------------------

# Lambda IAM  Role
module "lambda_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "lambda_function_iam_role"
  role_description   = "lambda_function_iam_role"
  policy_name        = "lambda_function_iam_policy"
  policy_description = "lambda_function_iam_policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            }            
        ]
    }
    EOF
}

module "table_sanity_check_function" {
  source        = "./modules/lambda"
  function_name = "table-sanity-check"
  role_arn      = module.lambda_function_iam_role.arn
  permissions   = []
  env_variables = {}
  handler       = "table_sanity_check.lambda_handler"
  runtime       = "python3.12"
  s3_bucket     = module.table_sanity_check_function_code.bucket
  s3_key        = "table_sanity_check.zip"
}

module "extract_table_data_function" {
  source        = "./modules/lambda"
  function_name = "extract-table-data"
  role_arn      = module.lambda_function_iam_role.arn
  permissions   = []
  env_variables = {}
  handler       = "extract_table_data.lambda_handler"
  runtime       = "python3.12"
  s3_bucket     = module.extract_table_data_function_code.bucket
  s3_key        = "extract_table_data.zip"
}
