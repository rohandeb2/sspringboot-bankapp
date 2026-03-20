# global/s3/main.tf

# 1. The S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${var.project_name}-terraform-state-${var.aws_account_id}"
  force_destroy = false # NEVER allow automated deletion of state files

  tags = merge(var.common_tags, { 
    Name = "${var.project_name}-terraform-state"
    Tier = "Global"
  })
}

# 2. Enable Versioning (Crucial for State Recovery)
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Server-Side Encryption using the Security Module KMS Key
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# 4. Block All Public Access (Banking Standard)
resource "aws_s3_bucket_public_access_block" "state_privacy" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5. DynamoDB Table for State Locking
# This prevents two engineers from running 'terraform apply' at the same time
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-state-locks" })
}