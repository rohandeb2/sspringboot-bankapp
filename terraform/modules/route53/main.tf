# modules/route53/main.tf

# 1. Fetch the existing Hosted Zone
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# 2. Create Alias Record for the ALB
# Industry Best Practice: Use Alias over CNAME for the root/subdomain to the ALB
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "bank.${var.domain_name}" # Matches your bank.joakim.online
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# 3. DNS Validation Records for ACM Certificate
# This automates the SSL 'Pending Validation' state
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in var.acm_domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}