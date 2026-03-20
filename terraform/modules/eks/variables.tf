variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "private_app_subnet_ids" {
  description = "List of private app subnet IDs for EKS"
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for high availability"
  }
}