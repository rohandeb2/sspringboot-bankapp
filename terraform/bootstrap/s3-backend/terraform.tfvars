project_name = "bankapp-prod"

environment  = "prod"

region = "us-east-1"

kms_key_arn = "arn:aws:kms:us-east-1:959589242185:key/35540e64-8e39-426d-b47b-d0613ece2c1c"

# Standard Tagging Policy
common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}
