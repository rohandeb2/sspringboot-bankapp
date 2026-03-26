variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string) # key-value pairs for tagging
  default     = {}
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days > 0
    error_message = "Log retention must be greater than 0"
  }
}

variable "kms_key_arn" {
  description = "KMS Key ARN for encrypting CloudWatch logs"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS Topic ARN for alarm notifications"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch dashboard"
  type        = string
}