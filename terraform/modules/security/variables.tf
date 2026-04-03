variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}
variable alb_sg_id {
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security resources will be created"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}