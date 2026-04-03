variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_app_subnets" {
  description = "List of CIDR blocks for private application subnets"
  type        = list(string)
}

variable "private_data_subnets" {
  description = "List of CIDR blocks for private data subnets"
  type        = list(string)
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}