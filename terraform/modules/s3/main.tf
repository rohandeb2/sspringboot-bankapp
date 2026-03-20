# modules/s3/main.tf

# 1. The S3 Bucket
resource "aws_s3_bucket" "main" {
  bucket        = "${var.project_name}-${var.bucket_purpose}-${var.environment}"
  force_destroy = var.environment == "prod" ? false : true # Prevent accidental deletion in prod

  tags = merge(var.common_tags, { 
    Name    = "${var.project_name}-${var.bucket_purpose}"
    Purpose = var.bucket_purpose
  })
}

# 2. Versioning - Critical for State files and Backups
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Encryption - Industry Standard AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 4. Block Public Access - Mandatory for Banking/Production
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5. Lifecycle Rules - Cost Optimization (Move old versions to Glacier)
# Update your existing Lifecycle resource
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  # Keep your existing "archive-old-versions" rule here...
  rule {
    id     = "archive-old-versions"
    status = "Enabled"
    # ... (your existing code)
  }

  # --- NEW LOKI LOG ROTATION RULE ---
  rule {
    id     = "loki-log-retention"
    status = "Enabled"

    # Move active logs to Glacier after 30 days
    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # Delete logs permanently after 90 days (Compliance Standard)
    expiration {
      days = 90
    }
  }
}