variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "domain_name" {
  description = "Base domain name (e.g., joakim.online)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Invalid domain name format"
  }
}