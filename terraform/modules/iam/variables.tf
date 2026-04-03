variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket the application will access"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the application"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name for the application"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}