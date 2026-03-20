variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "AWS Account ID must be a 12-digit number"
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encryption"
  type        = string
}