# prod/backend.tf

terraform {
  backend "s3" {
    # Replace these with the actual outputs from your Bootstrap S3 module
    bucket         = "bankapp-terraform-state-123456789012" 
    key            = "prod/terraform.tfstate" # Path within the bucket
    region         = "us-east-1"
    
    # Replace with the actual output from your Bootstrap DynamoDB module
    dynamodb_table = "bankapp-terraform-locks"
    
    encrypt        = true # AES256 encryption at rest
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Version pinning for production stability
    }
  }
}