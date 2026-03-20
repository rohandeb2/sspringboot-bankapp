# bootstrap/dynamodb-lock/main.tf

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # Cost-optimized for infrequent hits
  hash_key     = "LockID"         # Mandatory name for Terraform state locking

  # The attribute must be named exactly "LockID" and be a String (S)
  attribute {
    name = "LockID"
    type = "S"
  }

  # Prevent accidental deletion of the lock table
  deletion_protection_enabled = var.environment == "prod" ? true : false

  # TTL (Time to Live) is not needed for state locks, 
  # but point-in-time recovery is a "Senior" safety move.
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-terraform-locks"
    Tier = "Bootstrap"
  })
}