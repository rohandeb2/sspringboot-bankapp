project_name = "bankapp-prod"

environment  = "prod"

region = "us-east-1"

kms_key_arn = "arn:aws:kms:us-east-1:959589242185:key/2fc37909-27cf-4d9e-bc67-6c6737b731b5"

# Standard Tagging Policy
common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}
