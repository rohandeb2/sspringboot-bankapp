variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. prod, dev)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
}

variable "common_tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
}

variable "kubernetes_version" {
  description = "Version of EKS to deploy"
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
  description = "List of CIDR blocks for private database subnets"
  type        = list(string)
}

variable "db_instance_class" {
  description = "The instance type of the RDS database"
  type        = string
}

variable "db_name" {
  description = "The name of the database to create"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
}

variable "domain_name" {
  description = "The primary domain name for the application"
  type        = string
}

variable "namespace" {
  description = "The Kubernetes namespace for the app"
  type        = string
}

variable "service_account_name" {
  description = "The IAM service account name for EKS"
  type        = string
}