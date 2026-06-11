resource "aws_cloudwatch_log_group" "app_logs" {
  name = "/aws/eks/${var.project_name}/application"
  retention_in_days = var.log_retention_days
  kms_key_id = var.kms_key_arn
}

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name = "error-filter"
  pattern = "?Exception ?Error ?500"
  log_group_name = aws_cloudwatch_log_group.app_logs.name

  metric_transformation {
    name = "ErrorCount"
    namespace = "BankingApp/Metrics"
    value = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_error_alarm" {
  alarm_name = "${var.project_name}-error-alarm"
  metric_name = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name
  namespace = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].namespace

  threshold = 5
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  period = 60
  statistic = "Sum"

  alarm_actions = [var.sns_topic_arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        width = 12
        height = 6

        properties = {
          metrics = [
            [
              "BankingApp/Metrics",
              "ErrorCount"
            ]
          ]
          stat = "Sum"
          period = 300
          region = var.aws_region
          title = "errors"
        }
      }
    ]
  })
}