# Alerting runbook

Mimir ruler evaluates `mimir-rules`; Mimir Alertmanager routes by `severity` (critical hourly, warning every 4h, info dropped) to Slack `#eve-alerts`. Secrets: `platform/alerting/slack` (`webhook_url`), `platform/alerting/heartbeat` (`url`) in OpenBao, delivered by ESO.

## Watchdog
Always firing, routed only to the heartbeat receiver (healthchecks.io ping every 2 min). The external check alerts when pings stop: ruler, Alertmanager or the network path is down. Check: `kubectl -n monitoring get pods -l app.kubernetes.io/component=alertmanager`, then `AlertmanagerNotificationsFailing` in Mimir.

## Test
Prove delivery after any Mimir or Alertmanager change: set `eve_alert_pipeline_test_switch` to `vector(1)` in `platform-apps/observability/mimir/local/values.yaml`, merge, expect `AlertPipelineTest` in Slack within 2 min and a resolved notice after setting it back to `vector(0)`.

## Delivery failing
`AlertmanagerNotificationsFailing`: Slack webhook invalid or unreachable. Rotate the webhook in OpenBao; ESO resyncs within 5 min; Alertmanager reads the file on each notification.
