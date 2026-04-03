variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}


# variable "oidc_provider_arn" {
#   description = "OIDC provider ARN for IRSA (used by Karpenter)"
#   type        = string
# }

variable "private_app_subnet_ids" {
  description = "List of private app subnet IDs for EKS"
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for high availability"
  }
}