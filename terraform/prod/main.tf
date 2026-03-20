# prod/main.tf

# 1. Networking Layer
module "vpc" {
  source               = "../modules/networking"
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnets       = var.public_subnets
  private_app_subnets  = var.private_app_subnets
  private_data_subnets = var.private_data_subnets
  common_tags          = var.common_tags
}

# 2. Security Layer (KMS, Security Groups)
module "security" {
  source       = "../modules/security"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  common_tags  = var.common_tags
}

# 3. Compute Layer (EKS)
module "eks" {
  source                 = "../modules/eks"
  project_name           = var.project_name
  kubernetes_version     = "1.31"
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  # Ensure VPC is ready before cluster starts
  depends_on             = [module.vpc]
}

# 4. Database Layer (RDS)
module "rds" {
  source                  = "../modules/rds"
  project_name            = var.project_name
  environment             = "prod"
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  rds_sg_id               = module.security.rds_sg_id
  kms_key_arn             = module.security.kms_key_arn
  db_password             = var.db_password
  common_tags             = var.common_tags
}

# 5. Identity Layer (IRSA for your Banking App)
module "iam" {
  source            = "../modules/iam"
  project_name      = var.project_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.cluster_oidc_issuer_url
  s_bucket_arn      = module.s3_app.bucket_arn
  common_tags       = var.common_tags
}

# 1. Create the Bucket
module "loki_s3_bucket" {
  source         = "../modules/s3"
  project_name   = var.project_name
  bucket_purpose = "loki-logs"   # Be specific
  environment    = "prod"
  common_tags    = var.common_tags
}

# 2. IAM Policy for Loki (Least Privilege)
resource "aws_iam_policy" "loki_s3" {
  name        = "prod-loki-s3-access"
  description = "Allows Loki to read/write/delete logs in its own S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [module.loki_s3_bucket.bucket_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["${module.loki_s3_bucket.bucket_arn}/*"]
      }
    ]
  })
}

# 3. The IRSA Role (OIDC Link)
module "loki_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "loki-s3-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:loki-sa"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.loki_s3.arn
  }
}

# 1. Create the Tempo S3 Bucket
module "tempo_s3_bucket" {
  source         = "../modules/s3"
  project_name   = var.project_name
  bucket_purpose = "tempo-traces"
  environment    = "prod"
  common_tags    = var.common_tags
}

# 2. IAM Policy for Tempo
resource "aws_iam_policy" "tempo_s3" {
  name        = "prod-tempo-s3-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:PutObject", "s3:GetObject"]
        Resource = [module.tempo_s3_bucket.bucket_arn, "${module.tempo_s3_bucket.bucket_arn}/*"]
      }
    ]
  })
}

# 3. IRSA Role for Tempo
module "tempo_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "tempo-s3-role"
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:tempo-sa"]
    }
  }
  role_policy_arns = { policy = aws_iam_policy.tempo_s3.arn }
}