locals {
  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

# ---------------------------------------------------------------------------
# Helper: reusable assume-role policy for IRSA
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "irsa_assume" {
  for_each = {
    keda               = "system:serviceaccount:keda:keda-operator"
    evaluation_service = "system:serviceaccount:evaluation-service:evaluation-service"
    analytics_service  = "system:serviceaccount:analytics-service:analytics-service"
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [each.value]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# KEDA — reads SQS queue depth to drive autoscaling
# ---------------------------------------------------------------------------
resource "aws_iam_role" "keda" {
  name               = "${var.name_prefix}-keda"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["keda"].json
}

resource "aws_iam_policy" "keda" {
  name        = "${var.name_prefix}-keda-sqs-read"
  description = "Allows KEDA operator to read SQS queue metrics for ScaledObject"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [var.sqs_queue_arn, var.sqs_dlq_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "keda" {
  policy_arn = aws_iam_policy.keda.arn
  role       = aws_iam_role.keda.name
}

# ---------------------------------------------------------------------------
# evaluation-service — SQS producer (sends evaluation events)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "evaluation_service" {
  name               = "${var.name_prefix}-evaluation-service"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["evaluation_service"].json
}

resource "aws_iam_policy" "evaluation_service" {
  name        = "${var.name_prefix}-evaluation-service-sqs"
  description = "Allows evaluation-service to produce messages to SQS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "evaluation_service" {
  policy_arn = aws_iam_policy.evaluation_service.arn
  role       = aws_iam_role.evaluation_service.name
}

# ---------------------------------------------------------------------------
# analytics-service — SQS consumer + DynamoDB writer
# ---------------------------------------------------------------------------
resource "aws_iam_role" "analytics_service" {
  name               = "${var.name_prefix}-analytics-service"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["analytics_service"].json
}

resource "aws_iam_policy" "analytics_service" {
  name        = "${var.name_prefix}-analytics-service-sqs-dynamo"
  description = "Allows analytics-service to consume SQS messages and write to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [var.sqs_queue_arn, var.sqs_dlq_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_service" {
  policy_arn = aws_iam_policy.analytics_service.arn
  role       = aws_iam_role.analytics_service.name
}
