# bootstrap/s3-backend/main.tf

# 1. The S3 Bucket for Terraform State
resource "aws_s3_bucket" "state_bucket" {
  bucket        = "${var.project_name}-terraform-state-${var.aws_account_id}"
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
  bucket = aws_s3_bucket.state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Server-Side Encryption (AES256 or KMS)
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4. Block Public Access - Non-negotiable for Banking security
resource "aws_s3_bucket_public_access_block" "state_privacy" {
  bucket = aws_s3_bucket.state_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5. Object Lock Configuration (Legal Hold/Compliance)
resource "aws_s3_bucket_object_lock_configuration" "state_lock" {
  bucket = aws_s3_bucket.state_bucket.id

  rule {
    default_retention {
      mode = "GOVERNANCE" # Allows authorized users to delete versions if needed
      days = 30
    }
  }
}