project_name = "bankapp-prod"

environment  = "prod"

region = "us-east-1"

kms_key_arn = "arn:aws:kms:us-east-1:959589242185:key/028b38f7-c041-4058-8bb3-2a30e9d4ded8"

common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}
