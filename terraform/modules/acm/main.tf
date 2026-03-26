# global/acm/main.tf

# 1. Request the Public SSL Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Subject Alternative Names (SANs) - Allows bank.joakim.online
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  tags = merge(var.common_tags, { 
    Name = "${var.project_name}-wildcard-cert" 
  })

  lifecycle {
    create_before_destroy = true # Mandatory for certificates to prevent downtime
  }
}

# 2. Certificate Validation Logic
# This resource doesn't "do" anything in AWS; it tells Terraform to 
# wait until the DNS records are verified before marking the cert as 'ready'.
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = var.validation_record_fqdns
}