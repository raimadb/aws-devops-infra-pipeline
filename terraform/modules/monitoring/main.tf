data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
  # CloudWatch wants "targetgroup/name/id", which is the last part of the ARN.
  target_group_suffix = split(":", var.target_group_arn)[5]
}

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${var.environment}-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "text"
        x          = 0
        y          = 0
        width      = 24
        height     = 1
        properties = { markdown = "## Compute: ECS Fargate service ${var.service_name}" }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "ECS CPU utilization (%)"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "ECS memory utilization (%)"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Running tasks"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Fargate ephemeral storage (disk)"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["ECS/ContainerInsights", "EphemeralStorageUtilized", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            ["ECS/ContainerInsights", "EphemeralStorageReserved", "ClusterName", var.cluster_name, "ServiceName", var.service_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Network bytes in / out"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            ["ECS/ContainerInsights", "NetworkTxBytes", "ClusterName", var.cluster_name, "ServiceName", var.service_name]
          ]
        }
      },
      {
        type       = "text"
        x          = 0
        y          = 13
        width      = 24
        height     = 1
        properties = { markdown = "## Database: RDS ${var.db_identifier}" }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "RDS CPU utilization (%)"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title   = "RDS database connections"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS free storage (GB)"
          region = local.region
          view   = "timeSeries"
          period = 300
          metrics = [
            [{ expression = "m1/1024/1024/1024", label = "Free storage (GB)", id = "e1" }],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_identifier, { id = "m1", stat = "Average", visible = false }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "RDS freeable memory (MB)"
          region = local.region
          view   = "timeSeries"
          period = 300
          metrics = [
            [{ expression = "m1/1024/1024", label = "Freeable memory (MB)", id = "e1" }],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.db_identifier, { id = "m1", stat = "Average", visible = false }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "RDS read / write latency (seconds)"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.db_identifier],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.db_identifier]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "RDS read / write IOPS"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.db_identifier],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", var.db_identifier]
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${var.environment}-application"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Request rate (requests per minute)"
          region  = local.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Error rate (% of requests returning 5XX)"
          region = local.region
          view   = "timeSeries"
          period = 60
          metrics = [
            [{ expression = "100*m2/m1", label = "5XX error rate (%)", id = "e1" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { id = "m1", stat = "Sum", visible = false }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { id = "m2", stat = "Sum", visible = false }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "HTTP errors (counts)"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Response latency (seconds)"
          region = local.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "Average", label = "average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95", label = "p95" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Healthy vs unhealthy targets"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.target_group_suffix, "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.target_group_suffix, "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 8
        properties = {
          title  = "Recent application logs"
          region = local.region
          view   = "table"
          query  = "SOURCE '${var.log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
        }
      }
    ]
  })
}
