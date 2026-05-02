project_name = "bankapp-prod"

environment  = "prod"

region = "us-east-1"

kms_key_arn = "arn:aws:kms:us-east-1:959589242185:key/0463764f-bc03-4585-98f7-5b9410d21342"

# Standard Tagging Policy
common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}
