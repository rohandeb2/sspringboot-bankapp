# bootstrap/s3-backend/main.tf
provider "aws" {
  region = "${var.region}"
}
# 1. The S3 Bucket for Terraform State
resource "aws_s3_bucket" "state_bucket" {
  bucket        = "bankapp-terraform-state-874516984521" # Must be globally unique
  force_destroy = false # Mandatory: prevent accidental deletion of state

  # Object Lock is a senior-level compliance feature
  object_lock_enabled = true 

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-state-backend"
    Tier = "Bootstrap"
  })
}

# 2. Versioning - Critical for state recovery
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket        = "bankapp-terraform-state-874516984521"  
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Server-Side Encryption (AES256 or KMS)
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket        = "bankapp-terraform-state-874516984521" 

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# 4. Block Public Access - Non-negotiable for Banking security
resource "aws_s3_bucket_public_access_block" "state_privacy" {
  bucket = "bankapp-terraform-state-874516984521"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5. Object Lock Configuration (Legal Hold/Compliance)
resource "aws_s3_bucket_object_lock_configuration" "state_lock" {
  bucket = "bankapp-terraform-state-874516984521"

  rule {
    default_retention {
      mode = "GOVERNANCE" # Allows authorized users to delete versions if needed
      days = 30
    }
  }
}