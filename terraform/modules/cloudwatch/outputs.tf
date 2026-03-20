output "log_group_name" {
  value = aws_cloudwatch_log_group.app_logs.name
}

output "log_group_arn" {
  value = aws_cloudwatch_log_group.app_logs.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}