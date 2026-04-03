# 1. Fetch existing hosted zone
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# 2. Create DNS record pointing to ALB
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# NOTE: The cert_validation and acm_certificate_validation blocks 
# HAVE BEEN REMOVED from here because they are now in the ACM module.
# This points the root domain (rohandevops.co.in) to the ALB
resource "aws_route53_record" "root_domain" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "rohandevops.co.in" # The root domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# If you want to use www.rohandevops.co.in as well:
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.rohandevops.co.in"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

