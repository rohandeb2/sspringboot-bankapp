# modules/iam/main.tf

# IAM policy granting app permissions to access S3 and Secrets Manager
resource "aws_iam_policy" "app_policy" {
  name        = "${var.project_name}-app-policy" # policy name
  description = "Policy for Spring Boot Banking App to access S3 and Secrets" # purpose

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow" # allow access
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"] # S3 operations
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"] # bucket + objects
      },
      {
        Effect   = "Allow" # allow access
        Action   = ["secretsmanager:GetSecretValue"] # read secrets
        Resource = ["*"] # The application can read any secret from AWS Secrets Manager.
      }
    ]
  })
}

# creating an IAM Role for  Kubernetes pod using IRSA (IAM Roles for Service Accounts)
resource "aws_iam_role" "app_role" {
  name = "${var.project_name}-app-irsa-role" # role name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity" # Allows a Kubernetes pod to assume this IAM role
        Effect = "Allow" # allow assumption
        Principal = {
          Federated = var.oidc_provider_arn # Trusts your EKS cluster’s OIDC provider for authentication
        }
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}" # Only this specific service account can use the role
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com" #The aud condition ensures the token is intended for AWS STS (sts.amazonaws.com) and not for another service, adding an extra layer of security.
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, { Name = "${var.project_name}-app-irsa" }) # tagging
}

# Attach the IAM policy to the role
resource "aws_iam_role_policy_attachment" "app_attach" {
  policy_arn = aws_iam_policy.app_policy.arn # attach policy
  role       = aws_iam_role.app_role.name   # attach to role
}

# modules/iam/main.tf
module "velero_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-velero-irsa"
  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["velero:velero-server"] # Matches Velero SA
    }
  }
  # Allows Velero to create EBS snapshots
  role_policy_arns = {
    ebs = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

# Create IAM Policy → defines what actions are allowed
# Create IAM Role → defines who can use those permissions
# Attach Policy to Role → connects both


# In this module, I first create an IAM policy that defines what actions are allowed, such as accessing 
# a specific S3 bucket and reading secrets from “For example, if a pod wants to store data in S3:”

# The pod runs with a Kubernetes service account
# That service account is linked to the IAM role (IRSA)
# The pod requests a token → AWS STS verifies it via OIDC
# If valid, AWS gives temporary credentials
# Using those credentials, the pod can:
# Put object
# Get object
# List bucket
# Secrets Manager. Then, I create an IAM role using IRSA, 
# which allows a specific Kubernetes service account in my EKS cluster to securely assume this role using 
# OIDC. Finally, I attach the policy to the role, so that once the pod assumes the role, it gets the 
# required permissions to access AWS resources

