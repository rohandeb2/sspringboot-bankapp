variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "private_data_subnet_ids" {
  description = "Private data subnet IDs for RDS"
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability"
  }
}

variable "rds_sg_id" {
  description = "Security Group ID for RDS instance"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS Key ARN for encryption"
  type        = string
}

# DB Specifics

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "bankappdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Password must be at least 8 characters long"
  }
}