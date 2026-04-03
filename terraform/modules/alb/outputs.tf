output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}
output "alb_zone_id" {
  value = aws_lb.main.zone_id # Replace 'main' with your aws_lb resource name
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_security_group_id" {
  description = "Security group ID of the ALB"
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.app.arn
}