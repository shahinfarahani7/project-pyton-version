locals {
  artifact_services = toset(["file", "result", "model-registry"])
  secret_services = toset([
    "identity",
    "customer",
    "file",
    "task-intake",
    "pricing",
    "worker-registry",
    "result",
    "verification",
    "billing",
    "ledger",
    "reward",
    "claim",
    "fraud",
    "webhook",
    "model-registry",
    "operations",
    "event-relay",
  ])
}

resource "aws_iam_role_policy" "workload" {
  for_each = aws_iam_role.workload
  name     = "${local.name}-${each.key}-least-privilege"
  role     = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      contains(local.artifact_services, each.key) ? [{
        Sid    = "ArtifactObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
        ]
        Resource = ["${aws_s3_bucket.artifacts.arn}/*"]
        }, {
        Sid      = "ArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.artifacts.arn]
      }] : [],
      contains(local.secret_services, each.key) ? [{
        Sid      = "ReadApprovedSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = var.workload_secret_arns
      }] : [],
      [{
        Sid      = "UsePlatformKms"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.platform.arn]
      }]
    )
  })
}
