# modules/s3/main.tf

# S3 bucket for storing application data, logs, or backups
resource "aws_s3_bucket" "main" {
  bucket        = "${var.project_name}-${var.bucket_purpose}-${var.environment}" # unique bucket name
  force_destroy = var.environment == "prod" ? false : true # prevent accidental deletion in prod

  tags = merge(var.common_tags, { 
    Name    = "${var.project_name}-${var.bucket_purpose}" # bucket name tag
    Purpose = var.bucket_purpose                         # logical purpose of bucket
  })
}

# Enable versioning to keep multiple versions of objects (useful for backups and recovery)
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled" # turns on object versioning
  }
}

# Enable server-side encryption using AES256 for data protection at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# Block all public access to enforce security (critical for banking/production workloads)
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true # prevents public ACLs
  block_public_policy     = true # prevents public bucket policies
  ignore_public_acls      = true # ignores existing public ACLs
  restrict_public_buckets = true # restricts public bucket access
}

# Lifecycle rules to optimize storage cost and manage log/data retention
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  # Existing rule for archiving older versions (implementation not shown)
  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Log retention rule for Loki logs (cost + compliance management)
  rule {
    id     = "loki-log-retention" # lifecycle rule for logs
    status = "Enabled"            # activates the rule

    transition {
      days          = 30         # move logs after 30 days
      storage_class = "GLACIER"  # cheaper cold storage
    }

    expiration {
      days = 90 # delete logs permanently after 90 days
    }
  }
}