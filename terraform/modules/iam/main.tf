# modules/iam/main.tf

# 1. Policy for Spring Boot App (Access to S3 and Secrets Manager)
resource "aws_iam_policy" "app_policy" {
  name        = "${var.project_name}-app-policy"
  description = "Policy for Spring Boot Banking App to access S3 and Secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["*"] # Narrow this down to specific Secret ARN in prod
      }
    ]
  })
}

# 2. IAM Role for the Kubernetes Service Account (IRSA)
resource "aws_iam_role" "app_role" {
  name = "${var.project_name}-app-irsa-role"

  # The Trust Relationship - This is the "Magic" of IRSA
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, { Name = "${var.project_name}-app-irsa" })
}

# 3. Attach Policy to Role
resource "aws_iam_role_policy_attachment" "app_attach" {
  policy_arn = aws_iam_policy.app_policy.arn
  role       = aws_iam_role.app_role.name
}