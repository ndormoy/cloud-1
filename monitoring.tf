# ---------------------------------------------------------------------------- #
#                                SNS                                           #
# ---------------------------------------------------------------------------- #

resource "aws_sns_topic" "alerts" {
  provider = aws.default

  name = "alerts-topic-${local.project_name}"
}

resource "aws_sns_topic_subscription" "email_alerts" {
  provider = aws.default

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# ---------------------------------------------------------------------------- #
#                                CLOUDWATCH                                    #
# ---------------------------------------------------------------------------- #

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  provider = aws.default

  alarm_name          = "unhealthy-hosts-alarm-${local.project_name}"
  alarm_description   = "Triggers if an EC2 instance becomes unhealthy in the ALB"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  period              = 60
  threshold           = 1
  statistic           = "Maximum"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"

  dimensions = {
    TargetGroup  = module.alb.target_groups["asg_web_targets"].arn_suffix
    LoadBalancer = module.alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
