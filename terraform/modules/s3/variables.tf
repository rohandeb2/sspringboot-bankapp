variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
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

variable "bucket_purpose" {
  description = "Purpose of the bucket (e.g., terraform-state, app-backups, logs)"
  type        = string

  validation {
    condition     = length(var.bucket_purpose) > 0
    error_message = "Bucket purpose cannot be empty"
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption"
  type        = string
}

