variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for EKS (used in IRSA)"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN the application will access"
  type        = string
}

# Kubernetes specific metadata for the Trust Policy

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "bank-app-sa"
}