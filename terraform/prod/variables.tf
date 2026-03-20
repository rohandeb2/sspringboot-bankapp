variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "bankapp-prod"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "At least 2 public subnets required"
  }
}

variable "private_app_subnets" {
  description = "List of private app subnet CIDR blocks"
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnets) >= 2
    error_message = "At least 2 private app subnets required"
  }
}

variable "private_data_subnets" {
  description = "List of private data subnet CIDR blocks"
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnets) >= 2
    error_message = "At least 2 private data subnets required"
  }
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Password must be at least 8 characters"
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)

  default = {
    Project   = "Banking-System"
    ManagedBy = "Terraform"
    Owner     = "DevOps-Team"
  }
}