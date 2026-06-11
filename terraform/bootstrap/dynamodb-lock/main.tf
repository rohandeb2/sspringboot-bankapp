provider "aws" {
  region = "${var.region}"
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "bankapp-terraform-locks-8446176321459" 
  billing_mode = "PAY_PER_REQUEST" 
  hash_key     = "LockID"         
  attribute {
    name = "LockID"
    type = "S"
  }
  deletion_protection_enabled = var.environment == "prod" ? true : false

  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-terraform-locks"
    Tier = "Bootstrap"
  })
}
