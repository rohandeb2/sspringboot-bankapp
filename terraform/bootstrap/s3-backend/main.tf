provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state_bucket" {
  bucket              = "bankapp-terraform-state-874516984521"
  force_destroy       = false
  object_lock_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-state-backend"
    Tier = "Bootstrap"
  })
}

resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.state_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state_privacy" {
  bucket = aws_s3_bucket.state_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object_lock_configuration" "state_lock" {
  bucket = aws_s3_bucket.state_bucket.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }
}