variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (e.g., joakim.online)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Invalid domain name format"
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# This comes from the Route 53 module output after records are created
variable "validation_record_fqdns" {
  description = "List of FQDNs for DNS validation"
  type        = list(string)

  validation {
    condition     = length(var.validation_record_fqdns) > 0
    error_message = "At least one validation record FQDN is required"
  }
}