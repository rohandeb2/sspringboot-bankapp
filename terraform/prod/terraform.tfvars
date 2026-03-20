# prod/terraform.tfvars

# Project Metadata
project_name = "bankapp-prod"
environment  = "prod"

# Networking - Designing for HA (High Availability)
vpc_cidr             = "10.0.0.0/16"
public_subnets       = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnets  = ["10.0.10.0/24", "10.0.11.0/24"] # For EKS Nodes
private_data_subnets = ["10.0.20.0/24", "10.0.21.0/24"] # For RDS

# Database Configuration
# Note: The password should ideally be passed via environment variable (TF_VAR_db_password)
db_username       = "bankadmin"
db_instance_class = "db.t3.medium" # Production scale

# Domain & SSL
domain_name = "joakim.online"

# Standard Tagging Policy
common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}