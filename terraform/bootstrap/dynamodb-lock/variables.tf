variable "project_name" {
  type        = string
  description = "Project name, e.g., bankapp"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., bootstrap or prod)"
}

variable "common_tags" {
  type        = map(string)
  description = "Standard resource tagging"
}