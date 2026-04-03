variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "private_data_subnet_ids" {
  description = "List of private data subnet IDs for RDS"
  type        = list(string)
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "rds_sg_id" {
  description = "Security group ID for RDS access"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for RDS encryption"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev/stage/prod)"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}