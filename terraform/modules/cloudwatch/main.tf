# modules/cloudwatch/main.tf

# Log group : We create a log group in CloudWatch to organize and store logs from an application 
# in one place so we can monitor, search, and analyze logs easily, control retention (cost), 
# and apply security (encryption, access control)
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/eks/${var.project_name}/application" # log group path
  retention_in_days = var.log_retention_days # log retention to control cost
  kms_key_id        = var.kms_key_arn        # encrypt logs for security/compliance

  tags = merge(var.common_tags, { Name = "${var.project_name}-app-logs" }) # tagging
}

# Metric filter to detect errors from application logs
#It converts unstructured logs into measurable data so you can trigger alarms when errors increase.
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "SpringBootErrorCount" # filter name
  pattern        = "?Exception ?Error ?500" # log patterns to match errors
  #? = match if the word exists anywhere in the log line (not exact match)
  log_group_name = aws_cloudwatch_log_group.app_logs.name # source log group

  metric_transformation {
    name      = "ErrorCount" # metric name
    namespace = "BankingApp/Metrics" # custom namespace
    value     = "1" # increments metric per match
  }
}

# It alerts you when your application error rate becomes too high
resource "aws_cloudwatch_metric_alarm" "app_error_alarm" {
  alarm_name          = "${var.project_name}-high-error-rate" # alarm name
  comparison_operator = "GreaterThanOrEqualToThreshold" # trigger condition
  evaluation_periods  = "2" # Alarm checks the metric over 2 consecutive time periods before triggering
  metric_name         = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name #The name of the metric you created (e.g., ErrorCount) that the alarm is monitoring.
  namespace           = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].namespace # A logical grouping of metrics (here: BankingApp/Metrics) to separate your app metrics from others
  period              = "60" # evaluation window (seconds)
  statistic           = "Sum" # It calculates the total count of errors in each period (adds up all matching events).
  threshold           = "5" # threshold for alarm
  alarm_description   = "This alarm fires if Spring Boot throws more than 5 errors in 2 minutes" # description
  alarm_actions       = [var.sns_topic_arn] # notification target (SNS)

  tags = var.common_tags # tagging
}

# CloudWatch dashboard for visual monitoring of key metrics
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-overview" # dashboard name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric" # widget type
        width  = 12 # widget width
        height = 6 # widget height
        properties = {
          metrics = [
            [aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].namespace, aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name] # error metric
            #Show the ErrorCount metric from the BankingApp/Metrics namespace on the dashboard
          ]
          period = 300 # 5-minute aggregation
          stat   = "Sum" # sum of errors
          region = var.aws_region # region
          title  = "Application Errors" # chart title
        }
      }
    ]
  })
}