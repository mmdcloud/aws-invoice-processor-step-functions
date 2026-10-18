data "aws_caller_identity" "current" {}

# SNS Topic Policy allowing the account owner and Step Functions
data "aws_iam_policy_document" "sns_topic_policy_document" {
  statement {
    sid     = "AllowAccountOwner"
    effect  = "Allow"
    actions = [
      "SNS:Publish",
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_sns_topic.topic.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid     = "AllowStepFunctions"
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    resources = [aws_sns_topic.topic.arn]
  }
}

resource "aws_sns_topic_policy" "sns_topic_policy" {
  arn    = aws_sns_topic.topic.arn
  policy = data.aws_iam_policy_document.sns_topic_policy_document.json
}

# SNS Topic for notifying users about the state changes in MediaConvert Job
resource "aws_sns_topic" "topic" {
  name = var.topic_name
  tags = {
    Name = var.topic_name
  }
}

# SNS Subscription
resource "aws_sns_topic_subscription" "subscription" {
  count     = length(var.subscriptions)
  topic_arn = aws_sns_topic.topic.arn
  protocol  = var.subscriptions[count.index].protocol
  endpoint  = var.subscriptions[count.index].endpoint
}
