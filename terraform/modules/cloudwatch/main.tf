# modules/cloudwatch/main.tf

# 1. Log Group for Spring Boot Application
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/eks/${var.project_name}/application"
  retention_in_days = var.log_retention_days # Best Practice: Don't keep logs forever (cost)
  kms_key_id        = var.kms_key_arn        # Encrypt logs for banking compliance

  tags = merge(var.common_tags, { Name = "${var.project_name}-app-logs" })
}

# 2. Metric Filter to Detect 5xx Errors in Java Logs
# Scans logs for "Internal Server Error" or "Exception"
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "SpringBootErrorCount"
  pattern        = "?Exception ?Error ?500"
  log_group_name = aws_cloudwatch_log_group.app_logs.name

  metric_transformation {
    name      = "ErrorCount"
    namespace = "BankingApp/Metrics"
    value     = "1"
  }
}

# 3. CloudWatch Alarm for High Error Rate
resource "aws_cloudwatch_metric_alarm" "app_error_alarm" {
  alarm_name          = "${var.project_name}-high-error-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].namespace
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This alarm fires if Spring Boot throws more than 5 errors in 2 minutes"
  alarm_actions       = [var.sns_topic_arn]

  tags = var.common_tags
}

# 4. Dashboard for High-Level Monitoring
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            [aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].namespace, aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Application Errors"
        }
      }
    ]
  })
}