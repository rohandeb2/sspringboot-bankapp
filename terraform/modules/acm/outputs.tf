output "certificate_arn" {
  value       = aws_acm_certificate.main.arn
  description = "The ARN of the validated certificate"
}

output "domain_validation_options" {
  value       = aws_acm_certificate.main.domain_validation_options
  description = "Pass this to the Route 53 module for DNS record creation"
}