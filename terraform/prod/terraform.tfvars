# prod/terraform.tfvars

# Project Metadata
project_name = "bankapp-prod"

environment  = "prod"

region = "us-east-1"

kms_key_arn = "arn:aws:kms:us-east-1:959589242185:key/893d6b45-38e3-42b5-9d16-6ea26fa73a88"

# Standard Tagging Policy
common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}

kubernetes_version = "1.31"

vpc_cidr             = "10.0.0.0/16"

public_subnets = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

private_app_subnets = [
  "10.0.3.0/24",
  "10.0.4.0/24"
]



private_data_subnets = [
  "10.0.5.0/24",
  "10.0.6.0/24"
]


db_instance_class = "db.t4g.micro"

db_name = "bankappdb"

log_retention_days = 7

# Domain & SSL
domain_name = "rohandevops.co.in"



namespace = "banking-prod"

service_account_name = "bankapp-banking-platform"
