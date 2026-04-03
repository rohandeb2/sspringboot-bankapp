variable "domain_name" {
  description = "Primary domain name for the ACM certificate"
  type        = string
}

variable "project_name" {
  description = "Project name used for tagging"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}
variable "route53_zone_id" {
  description = "The Route53 Hosted Zone ID"
  type        = string
}