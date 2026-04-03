variable "region" {
  description = "AWS region where DynamoDB lock table will be created"
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

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}