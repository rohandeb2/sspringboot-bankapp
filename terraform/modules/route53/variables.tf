variable "domain_name" {
  description = "Domain name for Route53 hosted zone"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  type        = string
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the ALB"
  type        = string
}

# variable "certificate_arn" {
#   description = "ARN of the ACM certificate"
#   type        = string
# }

# variable "acm_domain_validation_options" {
#   description = "Domain validation options from ACM certificate"
#   type = list(object({
#     domain_name           = string
#     resource_record_name  = string
#     resource_record_value = string
#     resource_record_type  = string
#   }))
# }