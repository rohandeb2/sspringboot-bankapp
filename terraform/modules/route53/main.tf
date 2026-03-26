# modules/route53/main.tf

# Fetch existing hosted zone from Route53
data "aws_route53_zone" "main" {
  name         = var.domain_name   # domain name to lookup
  private_zone = false # this means it is a PUBLIC hosted zone, accessible over the internet (used for real domains like your website)
}

# Create DNS record pointing to ALB (recommended: Alias instead of CNAME)
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id # zone_id tells AWS in which domain (hosted zone) the DNS record should be created
  name = "api.${var.domain_name}" # creates a subdomain like bank.example.com
  type = "A"                       # defines an A record (maps domain name → IPv4/ALB)                             # A record for IPv4

  alias {
    name                   = var.alb_dns_name   # ALB DNS name
    zone_id                = var.alb_zone_id    # ALB hosted zone ID
    evaluate_target_health = true               # enables health checks
  }
}

#This resource dynamically creates Route 53 records for ACM certificate validation using the 
#domain validation options provided by ACM.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in var.acm_domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name   # DNS name provided by ACM for validation
      record = dvo.resource_record_value  # value that proves domain ownership
      type   = dvo.resource_record_type   # record type (usually CNAME)
    }
  }

  allow_overwrite = true                    # replaces record if it already exists
  name            = each.value.name         # creates the validation DNS name
  records         = [each.value.record]     # sets the validation value
  ttl             = 60                      # low TTL for quick DNS propagation
  type            = each.value.type         # record type (CNAME from ACM)
  zone_id         = data.aws_route53_zone.main.zone_id # which domain (hosted zone) to create record in
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn = var.certificate_arn

  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation :
    record.fqdn
  ]
}