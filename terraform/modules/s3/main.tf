# S3 Bucket
resource "aws_s3_bucket" "bucket" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags = {
    Name = var.bucket_name
  }
}

# Creating objects
resource "aws_s3_object" "object" {
  count  = length(var.objects)
  bucket = aws_s3_bucket.bucket.id
  source = var.objects[count.index].source
  key    = var.objects[count.index].key
}

# Bucket versioning configuration
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = var.versioning_enabled
  }
}

# Server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.kms_master_key_id
    }
  }
}

# S3 Block Public Access
resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# Bucket cors configuration
resource "aws_s3_bucket_cors_configuration" "cors" {
  count  = length(var.cors) > 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id
  dynamic "cors_rule" {
    for_each = var.cors
    content {
      allowed_headers = cors_rule.value["allowed_headers"]
      allowed_methods = cors_rule.value["allowed_methods"]
      allowed_origins = cors_rule.value["allowed_origins"]
      max_age_seconds = cors_rule.value["max_age_seconds"]
    }
  }
}

# Enforce TLS 1.2+ / HTTPS only requests
data "aws_iam_policy_document" "tls_enforcement" {
  count = var.enforce_tls ? 1 : 0

  statement {
    sid     = "EnforceTLSRequestsOnly"
    effect  = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Bucket policy
resource "aws_s3_bucket_policy" "bucket_policy" {
  count  = (var.bucket_policy != "" || var.enforce_tls) ? 1 : 0
  bucket = aws_s3_bucket.bucket.id
  policy = var.bucket_policy != "" ? var.bucket_policy : data.aws_iam_policy_document.tls_enforcement[0].json

  depends_on = [aws_s3_bucket_public_access_block.public_access_block]
}

# Specifying bucket notification configuration
resource "aws_s3_bucket_notification" "bucket_notification" {
  count  = (length(var.bucket_notification.queue) > 0 || length(var.bucket_notification.lambda_function) > 0) ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  dynamic "queue" {
    for_each = var.bucket_notification.queue
    content {
      queue_arn = queue.value["queue_arn"]
      events    = queue.value["events"]
    }
  }
  dynamic "lambda_function" {
    for_each = var.bucket_notification.lambda_function
    content {
      lambda_function_arn = lambda_function.value["lambda_function_arn"]
      events              = lambda_function.value["events"]
    }
  }
}
