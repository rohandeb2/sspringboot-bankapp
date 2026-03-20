variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "Invalid VPC CIDR block"
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)  #type = map(string) → a collection of key-value pairs
  default     = {}  #empty by default (no tags unless you provide them)
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string) #list= a collection (array) of values

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "At least 2 public subnets are required"
  }
}

variable "private_app_subnets" {
  description = "List of private app subnet CIDR blocks"
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnets) >= 2
    error_message = "At least 2 private app subnets are required"
  }
}

variable "private_data_subnets" {
  description = "List of private data subnet CIDR blocks"
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnets) >= 2
    error_message = "At least 2 private data subnets are required"
  }
}