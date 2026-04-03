output "route53_record_fqdn" {
  description = "FQDN of the application DNS record"
  value       = aws_route53_record.app.fqdn
}

# output "certificate_validation_status" {
#   description = "Status of ACM certificate validation"
#   value       = aws_acm_certificate_validation.main.certificate_arn
# }

output "zone_id" {
  description = "ID of the Route53 hosted zone"
  value       = data.aws_route53_zone.main.zone_id
}