---
paths:
  - "platform-apps/{grafana,loki,mimir,tempo,minio,opentelemetry-operator,prometheus-operator-crds,kube-state-metrics,metrics-server,alloy,kube-prometheus-stack}/**"
  - "manifests/{otel,config-drift}/**"
---
# Observability

- **Target stack: LGTM plus OpenTelemetry**, live in local.
  - Mimir handles metrics, Loki logs, Tempo traces, and Grafana dashboards.
  - The stores use MinIO through the S3 API, so a cloud env swaps the endpoint and credentials, not the stack.
  - dev, stg and prod still run kube-prometheus-stack until they're migrated.
- **Collection is the OpenTelemetry Operator** (`manifests/otel/`):
  - a daemonset agent: OTLP, pod logs to Loki, traces to Tempo, metrics remote-written to Mimir;
  - a cluster collector whose Target Allocator discovers ServiceMonitors and PodMonitors.
  - *Not* Alloy alongside it: running both double-scraped and double-shipped.
- **`prometheus-operator-crds` only**, so charts' ServiceMonitors apply. No Prometheus Operator or server in LGTM envs.
- **Alerting is Mimir's Alertmanager.**
- **Grafana:** datasources are static in values. Dashboards are ConfigMaps labelled `grafana_dashboard: "1"`.
- **Apps opt into auto-instrumentation** through the `Instrumentation` CR.
- **Keep high-cardinality values out of Loki's index.** Send them as structured metadata (see `manifests/config-drift`).
