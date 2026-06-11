terraform {
  backend "s3" {
    bucket        = "bankapp-terraform-state-874516984521" 
    key            = "prod/terraform.tfstate" 
    region         = "us-east-1"
    dynamodb_table = "bankapp-terraform-locks-8446176321459"
    encrypt        = true 
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}