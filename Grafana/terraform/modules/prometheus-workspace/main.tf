# -----------------------------------------------------------------------------
# prometheus-workspace — Amazon Managed Prometheus (AMP) + alerting + SNS
#
# AMP is a fully managed, Prometheus-compatible metrics store. It does NOT
# scrape by itself — metric sources (a Prometheus server, the ADOT collector,
# or an agent) push data via REMOTE WRITE to the workspace's ingest endpoint.
# Grafana (and other PromQL clients) read via the query endpoint.
#
# Auth is SigV4 (IAM) — NO username/password. Writers need
# aps:RemoteWrite; readers need aps:QueryMetrics / aps:GetSeries etc.
#
# This module creates:
#   - the AMP workspace
#   - a RULE GROUP namespace with a RECORDING rule + an ALERTING rule (PromQL)
#   - an ALERT MANAGER definition routing firing alerts to SNS (via a receiver)
#   - the SNS topic (+ optional email sub) that alerts land on
#
# CloudOps/AMP exam notes:
#   - RECORDING rule = precompute an expensive query into a new series (perf/cost).
#   - ALERTING rule = fire when a PromQL expression is true for `for` duration.
#   - Alert manager (managed) routes alerts to receivers (here: SNS → fan-out to
#     EventBridge/Lambda for auto-remediation).
#   - Remote write = how Prometheus servers / containers send metrics in.
# -----------------------------------------------------------------------------

# =============================================================================
# The AMP workspace
# =============================================================================
resource "aws_prometheus_workspace" "this" {
  alias = "${var.prefix}-amp"
  tags  = { Name = "${var.prefix}-amp" }
}

# =============================================================================
# SNS topic for alerts (alert manager publishes here)
# =============================================================================
resource "aws_sns_topic" "alerts" {
  name = "${var.prefix}-amp-alerts"
  tags = { Name = "${var.prefix}-amp-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Allow Amazon Managed Prometheus (alert manager) to publish to the topic.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAMPPublish"
      Effect    = "Allow"
      Principal = { Service = "aps.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
    }]
  })
}

# =============================================================================
# Rule group namespace — a RECORDING rule + an ALERTING rule (PromQL)
#
# Written in the standard Prometheus rules YAML. These evaluate server-side in
# AMP against ingested metrics.
# =============================================================================
resource "aws_prometheus_rule_group_namespace" "this" {
  name         = "${var.prefix}-rules"
  workspace_id = aws_prometheus_workspace.this.id

  data = <<-YAML
    groups:
      - name: recording-rules
        rules:
          # Precompute per-instance CPU usage (expensive to compute ad hoc).
          - record: instance:node_cpu_utilization:rate5m
            expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

      - name: alerting-rules
        rules:
          # Fire if computed CPU utilization stays above 80% for 5 minutes.
          - alert: HighCPUUtilization
            expr: instance:node_cpu_utilization:rate5m > 80
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High CPU on {{ $labels.instance }}"
              description: "CPU > 80% for 5m on {{ $labels.instance }}"
  YAML
}

# =============================================================================
# Alert manager definition — route firing alerts to the SNS receiver
# =============================================================================
resource "aws_prometheus_alert_manager_definition" "this" {
  workspace_id = aws_prometheus_workspace.this.id

  definition = <<-YAML
    alertmanager_config: |
      route:
        receiver: 'sns-default'
        group_by: ['alertname']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 1h
      receivers:
        - name: 'sns-default'
          sns_configs:
            - topic_arn: ${aws_sns_topic.alerts.arn}
              sigv4:
                region: ${data.aws_region.current.name}
              subject: 'AMP alert'
  YAML

  depends_on = [aws_sns_topic_policy.alerts]
}

data "aws_region" "current" {}
