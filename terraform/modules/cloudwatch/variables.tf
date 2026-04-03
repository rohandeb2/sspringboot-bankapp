variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting CloudWatch logs"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch dashboard"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}