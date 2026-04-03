output "certificate_arn" {
  value = aws_acm_certificate_validation.main.certificate_arn
}

output "domain_name" {
  description = "Domain name of the certificate"
  value       = aws_acm_certificate.main.domain_name
}
output "domain_validation_options" {
  value = aws_acm_certificate.main.domain_validation_options
}

