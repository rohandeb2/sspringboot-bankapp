output "fqdn" {
  value = aws_route53_record.app.fqdn
}

output "hosted_zone_id" {
  value = data.aws_route53_zone.main.zone_id
}

output "validation_record_fqdns" {
  value = [
    for record in aws_route53_record.cert_validation :
    record.fqdn
  ]
}