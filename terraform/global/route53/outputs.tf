output "hosted_zone_id" {
  value       = aws_route53_zone.main.zone_id
  description = "The ID of the Hosted Zone for use in sub-modules"
}

output "name_servers" {
  value       = aws_route53_zone.main.name_servers
  description = "Update your domain registrar with these NS records"
}

output "health_check_id" {
  value = aws_route53_health_check.app_link.id
}