
resource "random_id" "id" {
  byte_length = 8
}

# -----------------------------------------------------------------------------------------
# SNS Configuration
# -----------------------------------------------------------------------------------------
module "invalid_invoice_error_topic" {
  source     = "./modules/sns"
  topic_name = "invalid-invoice-error-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
}

module "data_storage_failure_topic" {
  source     = "./modules/sns"
  topic_name = "data-storage-failure-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
}

# -----------------------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------------------
module "vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Project = "invoice-processor"
  }
}

# -----------------------------------------------------------------------------------------
# DynamoDb Configuration
# -----------------------------------------------------------------------------------------
module "invoice_records_dynamodb" {
  source = "./modules/dynamodb"
  name   = "invoice-records"
  attributes = [
    {
      name = "RecordId"
      type = "S"
    },
    {
      name = "filename"
      type = "S"
    }
  ]
  billing_mode          = "PAY_PER_REQUEST"
  hash_key              = "RecordId"
  range_key             = "filename"
  ttl_attribute_name    = "TimeToExist"
  ttl_attribute_enabled = true
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "invoices_bucket" {
  source             = "./modules/s3"
  bucket_name        = "invoices-${random_id.id.hex}"
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
    queue = [
      {
        queue_arn = module.document_event_queue.arn
        events    = ["s3:ObjectCreated:*"]
      }
    ]
    lambda_function = []
  }
}

module "extract_table_data_function_code" {
  source      = "./modules/s3"
  bucket_name = "extract-table-data-source-code--${random_id.id.hex}"
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
  bucket_name = "table-sanity-check-source-code--${random_id.id.hex}"
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

module "start_step_function_code" {
  source      = "./modules/s3"
  bucket_name = "start-step-function-source-code--${random_id.id.hex}"
  objects = [
    {
      key    = "start_step_function.zip"
      source = "./files/start_step_function.zip"
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
# SQS Config
# -----------------------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "document_event_queue_trigger" {
  event_source_arn                   = module.document_event_queue.arn
  function_name                      = module.start_step_function_lambda.arn
  enabled                            = true
  batch_size                         = 10
  maximum_batching_window_in_seconds = 60
}

# SQS Queue for buffering S3 events
module "document_event_queue" {
  source                        = "./modules/sqs"
  queue_name                    = "document-event-queue"
  delay_seconds                 = 0
  maxReceiveCount               = 3
  dlq_message_retention_seconds = 86400
  dlq_name                      = "document-event-dlq"
  max_message_size              = 262144
  message_retention_seconds     = 345600
  visibility_timeout_seconds    = 180
  receive_wait_time_seconds     = 20
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = "arn:aws:sqs:${var.region}:*:document-event-queue"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = module.invoices_bucket.arn
          }
        }
      }
    ]
  })
}

module "step_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "step_function_iam_role"
  role_description   = "step_function_iam_role"
  policy_name        = "step_function_iam_policy"
  policy_description = "step_function_iam_policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "states.amazonaws.com"
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
                  "lambda:InvokeFunction"
                ],
                "Resource": [
                    "${module.table_sanity_check_function.arn}",
                    "${module.extract_table_data_function.arn}"
                ],
                "Effect": "Allow"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "sns:Publish"
                ],
                "Resource": [
                    "${module.invalid_invoice_error_topic.topic_arn}",
                    "${module.data_storage_failure_topic.topic_arn}"
                ]
            }
        ]
    }
    EOF
}
# -----------------------------------------------------------------------------------------
# Step Function Configuration
# -----------------------------------------------------------------------------------------
module "step_function" {
  source   = "./modules/step-function"
  name     = "InvoiceProcessingWorkflow"
  role_arn = module.step_function_iam_role.arn
  definition = templatefile("${path.module}/files/step-function-definition.json", {
    table_sanity_check_function_arn = module.table_sanity_check_function.arn
    extract_table_data_function_arn = module.extract_table_data_function.arn
    invalid_invoice_error_topic_arn = module.invalid_invoice_error_topic.topic_arn
    data_storage_failure_topic_arn  = module.data_storage_failure_topic.topic_arn
  })
}

# -----------------------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------------------
module "lambda_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "lambda-function-iam-role"
  role_description   = "lambda-function-iam-role"
  policy_name        = "lambda-function-iam-policy"
  policy_description = "lambda-function-iam-policy"
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
            },
            {
                "Effect": "Allow",
                "Action": [
                    "textract:AnalyzeDocument"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:*"
                ],
                "Resource": [
                    "${module.invoices_bucket.arn}",
                    "${module.invoices_bucket.arn}/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query"
                ],
                "Resource": "${module.invoice_records_dynamodb.arn}"
            }
        ]
    }
    EOF
}

module "start_step_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "start-step-function-iam-role"
  role_description   = "start-step-function-iam-role"
  policy_name        = "start-step-function-iam-policy"
  policy_description = "start-step-function-iam-policy"
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
            },
            {
                "Effect": "Allow",
                "Action": [
                    "sqs:DeleteMessage",
                    "sqs:GetQueueAttributes",
                    "sqs:ReceiveMessage"
                ],
                "Resource": "${module.document_event_queue.arn}"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "states:StartExecution"
                ],
                "Resource": "${module.step_function.arn}"
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
  timeout       = 60
  handler       = "table_sanity_check.lambda_handler"
  runtime       = "python3.12"
  s3_bucket     = module.table_sanity_check_function_code.bucket
  s3_key        = "table_sanity_check.zip"
  depends_on    = [module.table_sanity_check_function_code]
}

module "extract_table_data_function" {
  source        = "./modules/lambda"
  function_name = "extract-table-data"
  role_arn      = module.lambda_function_iam_role.arn
  permissions   = []
  timeout       = 60
  env_variables = {}
  handler       = "extract_table_data.lambda_handler"
  runtime       = "python3.12"
  s3_bucket     = module.extract_table_data_function_code.bucket
  s3_key        = "extract_table_data.zip"
  depends_on    = [module.extract_table_data_function_code]
}

module "start_step_function_lambda" {
  source        = "./modules/lambda"
  function_name = "start-step-function"
  role_arn      = module.start_step_function_iam_role.arn
  permissions   = []
  timeout       = 60
  env_variables = {
    STEP_FUNCTION_ARN = module.step_function.arn
  }
  handler    = "start_step_function.lambda_handler"
  runtime    = "python3.12"
  s3_bucket  = module.start_step_function_code.bucket
  s3_key     = "start_step_function.zip"
  depends_on = [module.start_step_function_code]
}