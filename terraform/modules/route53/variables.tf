variable "domain_name" {
  description = "The root domain name (e.g., joakim.online)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name from the ALB module"
  type        = string
}

variable "alb_zone_id" {
  description = "Hosted zone ID from the ALB module"
  type        = string
}

variable "acm_domain_validation_options" {
  description = "Output from the ACM module for DNS validation"
  type        = any
}