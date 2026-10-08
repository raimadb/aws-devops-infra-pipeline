output "dashboard_urls" {
  value = {
    infrastructure = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.infrastructure.dashboard_name}"
    application    = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.application.dashboard_name}"
  }
}
