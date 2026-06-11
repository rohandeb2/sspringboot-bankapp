resource "aws_s3_bucket" "main" {
  bucket        = "${var.project_name}-${var.bucket_purpose}-${var.environment}" 
  force_destroy = var.environment == "prod" ? false : true 

  tags = merge(var.common_tags, { 
    Name    = "${var.project_name}-${var.bucket_purpose}" 
    Purpose = var.bucket_purpose                        
  })
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled" 
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true 
  block_public_policy     = true 
  ignore_public_acls      = true 
  restrict_public_buckets = true 
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "loki-log-retention" 
    status = "Enabled"            
    filter {}
    transition {
      days          = 30         
      storage_class = "GLACIER"  
    }

    expiration {
      days = 90 
    }
  }
}