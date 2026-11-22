# Alerting runbook

Mimir ruler evaluates `mimir-rules`; Mimir Alertmanager routes by `severity` (critical hourly, warning every 4h, info dropped) to Slack `#eve-alerts`. Secrets: `platform/alerting/slack` (`webhook_url`), `platform/alerting/heartbeat` (`url`) in OpenBao, delivered by ESO.

## Watchdog
Always firing, routed only to the heartbeat receiver (healthchecks.io ping every 2 min). The external check alerts when pings stop: ruler, Alertmanager or the network path is down. Check: `kubectl -n monitoring get pods -l app.kubernetes.io/component=alertmanager`, then `AlertmanagerNotificationsFailing` in Mimir.

## Test
Prove delivery after any Mimir or Alertmanager change: set `eve_alert_pipeline_test_switch` to `vector(1)` in `platform-apps/observability/mimir/local/values.yaml`, merge, expect `AlertPipelineTest` in Slack within 2 min and a resolved notice after setting it back to `vector(0)`.

## Delivery failing
`AlertmanagerNotificationsFailing`: Slack webhook invalid or unreachable. Rotate the webhook in OpenBao; ESO resyncs within 5 min; Alertmanager reads the file on each notification.

## Argo

`ArgoApplicationOutOfSync` (30m) / `ArgoApplicationUnhealthy` (15m). Open the app in Argo CD: a failed sync shows the resource message; `Degraded` means the workload is not coming up (pod events). Auto-sync apps that stay OutOfSync usually have a sync error (hook, webhook, CRD missing) or `Retrying` exhausted; fix in git, never in the cluster. `Missing`/`Unknown` after a repo move: hard refresh.

## Certificates

`CertificateNotReady` (1h) / `CertificateExpiringSoon` (14d). `kubectl describe certificate -n <ns> <name>`, then its Order and Challenge. DNS-01 (Let's Encrypt): token at OpenBao `platform/dns-provider/cloudflare`, TXT propagation. Private CA: the `platform-ca` issuer and its root secret. A certificate that cannot renew takes the HTTPS listener down when it expires.
