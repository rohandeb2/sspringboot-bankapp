variable "kms_key_arn" {
  description = "KMS Key ARN for encrypting the S3 bucket"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "Must be a valid KMS Key ARN."
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region where the S3 backend bucket will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string

  validation {
    condition     = length(var.project_name) > 2
    error_message = "Project name must be at least 3 characters long."
  }
}

variable "environment" {
  description = "Deployment environment (e.g., dev, stage, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, prod."
  }
}