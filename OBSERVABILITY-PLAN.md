# End-to-End Observability Plan: LGTM + Alloy + OpenTelemetry

Status: **draft, awaiting approval**
Scope: replace `kube-prometheus-stack` Prometheus storage with the Grafana LGTM stack (Loki / Grafana / Tempo / Mimir), use Alloy as the unified collector, accept OTLP from OpenTelemetry-instrumented apps. Run standalone in `local`; layout designed to scale to dev/stg/prod without restructuring.

## Goal

One pane of glass in Grafana over **metrics, logs, traces** for everything in the cluster, with:

- **Metrics** from Prometheus `/metrics` endpoints (existing) AND OTLP — stored in Mimir.
- **Logs** from every pod's stdout — stored in Loki.
- **Traces** from OTel-instrumented apps — stored in Tempo.
- **One agent** (Alloy) per node + cluster, replacing the kube-prometheus-stack scraper, Promtail-equivalent, and any standalone OTel collector.
- **Object storage** (MinIO locally; S3/GCS in prod) backing all three databases — same config path migrates 1:1.

## Architecture

```
┌────────────────────────── workloads ───────────────────────────┐
│  Apps emit: /metrics endpoints, stdout logs, OTLP (4317/4318)  │
└────────────────────────────────────────────────────────────────┘
                              │ scrape / tail / OTLP
                              ▼
┌──────────────────────── collection ────────────────────────────┐
│  Alloy (DaemonSet + Deployment)                                │
│   • Prometheus scrape (replaces kube-prom scraper)             │
│   • Log tailer with position state on PVC                      │
│   • OTLP receivers (gRPC 4317 / HTTP 4318)                     │
│   • Sends to Mimir / Loki / Tempo, optional remote_write       │
└────────────────────────────────────────────────────────────────┘
                              │
       ┌──────────────────────┼──────────────────────┐
       ▼                      ▼                      ▼
┌─── Mimir ─────┐    ┌──── Loki ────┐      ┌──── Tempo ────┐
│ metrics TSDB  │    │ log store    │      │ trace store   │
│ Prom-compat   │    │ LogQL        │      │ TraceQL       │
└───────┬───────┘    └──────┬───────┘      └───────┬───────┘
        └────────────────┬──┴──────────────────────┘
                         ▼
                  ┌── MinIO ──┐
                  │ S3-compat │
                  └─────┬─────┘
                        │
                        ▼ datasources
                 ┌── Grafana ──┐
                 └─────────────┘
```

## Phases (each = one platform-app, one Argo Application, one verification step)

Each phase is a discrete commit. Designed so `/loop` can execute one phase per iteration.

### Phase 0 — Prep
- [ ] Confirm kube-prometheus-stack stays running during transition. We keep Grafana + Alertmanager + operator; only Prometheus storage is replaced (eventually disabled).
- [ ] Sanity-check `standard` StorageClass has headroom for ~50Gi (MinIO data + Loki/Mimir/Tempo local caches if any).
- [ ] Decide tenancy: `local` env → single tenant `anonymous`. Plumb `X-Scope-OrgID` header path now so multi-tenant later is config-only.

### Phase 1 — MinIO (object store)
- Chart: `minio/minio` (single-node, distributed=false) in `monitoring-storage` namespace.
- Buckets to create (Helm `buckets:` value): `mimir-blocks`, `mimir-ruler`, `mimir-alertmanager`, `loki-chunks`, `loki-ruler`, `tempo-blocks`.
- Credentials in Helm values for local; **production: move to External Secrets Operator + Vault/SOPS**.
- syncWave: `-3` (must exist before any LGTM DB starts).
- Verify: `mc ls` shows all 6 buckets, Console reachable via Ingress at `local.minio.internal`.

### Phase 2 — Mimir (metrics)
- Chart: `grafana/mimir-distributed` in **monolithic** mode (single binary, all components in one StatefulSet).
- `mimir.structuredConfig.common.storage.backend: s3` → MinIO endpoint, bucket `mimir-blocks`.
- Ruler bucket: `mimir-ruler`. Alertmanager bucket: `mimir-alertmanager`.
- Push endpoint exposed via Service `mimir-nginx:80/api/v1/push` (Prometheus remote_write compatible).
- Retention: 30d locally (override `compactor.retention_period`). Set explicitly — default is unlimited.
- syncWave: `-1` (after MinIO).
- Verify: `curl mimir-nginx/ready` → 200. Push a synthetic metric and query via `/prometheus/api/v1/query`.

### Phase 3 — Loki (logs)
- Chart: `grafana/loki` in **SingleBinary** mode.
- `loki.storage.type: s3` → MinIO, bucket `loki-chunks`. Schema: TSDB index, last `v13`.
- Retention: 7d locally via `compactor.retention_enabled: true` + `limits_config.retention_period: 168h`.
- Push endpoint: `loki:3100/loki/api/v1/push`.
- syncWave: `-1` (after MinIO; parallel with Mimir/Tempo).
- Verify: `curl loki:3100/ready`, push a log line via API, query via LogQL `{job="manual"}`.

### Phase 4 — Tempo (traces)
- Chart: `grafana/tempo` (monolithic single-binary).
- `tempo.storage.trace.backend: s3` → MinIO, bucket `tempo-blocks`.
- OTLP ingest enabled (`receivers.otlp.protocols.grpc/http`).
- Retention: 72h locally.
- syncWave: `-1`.
- Verify: `curl tempo:3200/ready`, send synthetic trace via OTLP gRPC.

### Phase 5 — Alloy (unified collector)
- Chart: `grafana/alloy`.
- Topology: **DaemonSet** (per-node logs + node metrics) + **Deployment** (3 replicas eventually; 1 in local) for cluster-scope scraping and OTLP gateway.
- Single `alloy.config` River file with components:
  - `prometheus.scrape` mirroring the existing kube-prometheus-stack ServiceMonitor selectors.
  - `loki.source.kubernetes` for stdout tail.
  - `otelcol.receiver.otlp` on 4317/4318, fanout to `otelcol.processor.batch`.
  - `otelcol.exporter.otlp` → Tempo for traces; `prometheus.remote_write` → Mimir; `loki.write` → Loki.
- Position state on PVC so a restart doesn't replay all logs.
- syncWave: `0`.
- Verify: Alloy UI shows components healthy. Mimir receives kube-state-metrics. Loki receives a pod's logs. Tempo receives a test trace.

### Phase 6 — Grafana datasources
- Edit `kube-prometheus-stack/local/values.yaml`:
  - `grafana.additionalDataSources`: Mimir (default), Loki, Tempo.
  - Each datasource provisioned via the sidecar (no UI clicks). Linked via `derivedFields` (Loki → trace IDs → Tempo, Tempo → service → Mimir).
- Verify: Grafana Explore → all three sources show data. A traced request appears in Tempo and its logs appear in Loki via TraceID link.

### Phase 7 — Decommission Prometheus storage
- Edit `kube-prometheus-stack/local/values.yaml`:
  - `prometheus.enabled: false` (or disable just the StatefulSet, keep the Operator if you want CRDs to keep working).
  - Keep Alertmanager pointed at Mimir's ruler-generated alerts.
- The existing `ServiceMonitor` / `PodMonitor` CRs are still honored because the Operator keeps running and Alloy reads the same CRs via `prometheus.operator.servicemonitors`.
- Verify: no `prometheus-local-...` StatefulSet pods. Grafana dashboards still populate (queries go to Mimir).
- Verify: alerts still fire (use a forced test rule).

### Phase 8 — Production-scope checklist
Per-phase TODOs to revisit before going beyond `local`:

- [ ] MinIO → S3/GCS via IRSA / Workload Identity. No baked-in credentials.
- [ ] Mimir/Loki/Tempo: switch chart from monolithic to `simple-scalable` (Loki) or `distributed` (Mimir/Tempo). Same chart, value-only change.
- [ ] Alloy: scale Deployment to 3 replicas behind a Service; enable clustering (`clustering.enabled: true`) so scrape targets shard automatically.
- [ ] Tenancy: per-env `X-Scope-OrgID`. Datasources templated by tenant.
- [ ] Retention: lifecycle policies on the object store; Loki/Mimir compactor retention aligned.
- [ ] mTLS between Alloy and backends (Cilium-issued certs or cert-manager).
- [ ] Backup of Mimir/Loki/Tempo metadata (PVCs or repo of operator state).
- [ ] Tracing sampling: tail-based sampling at Alloy (`otelcol.processor.tail_sampling`) to bound Tempo write rate.
- [ ] Network policies / CiliumNetworkPolicy scoping each LGTM component (after the [[global-l7-visibility]] lesson — per-app, not cluster-wide).

## Where things live

| Component | Path |
|---|---|
| MinIO | `platform-apps/minio/local/{config,values}.yaml` |
| Mimir | `platform-apps/mimir/local/{config,values}.yaml` |
| Loki | `platform-apps/loki/local/{config,values}.yaml` |
| Tempo | `platform-apps/tempo/local/{config,values}.yaml` |
| Alloy | `platform-apps/alloy/local/{config,values}.yaml` |
| OTel Collector (optional) | `platform-apps/opentelemetry-collector/local/{config,values}.yaml` |
| Datasource changes | `platform-apps/kube-prometheus-stack/local/values.yaml` |
| Prometheus decom | `platform-apps/kube-prometheus-stack/local/values.yaml` |

## Rollback

Each phase is independent in git. To rollback any phase:

- Set its `config.yaml` → `enabled: "false"` and `git revert` the workload commit. Argo prunes the Application.
- Phase 7 (Prometheus decom) is the only one with stateful implications. Keep the existing PVC; flipping `prometheus.enabled` back on restores the previous TSDB intact.

## Open questions

1. **Single tenant or namespace=tenant?** Single is fine for `local`; namespace-as-tenant is a common pattern but requires Alloy adds `X-Scope-OrgID` per namespace.
2. **OTel Collector phase 6 — keep Alloy-only?** Alloy is OTLP-native, so a separate collector is redundant unless you specifically want OTel's processor ecosystem.
3. **Mimir Alertmanager vs. existing kube-prom Alertmanager?** Recommend keep kube-prom Alertmanager for now; route Mimir alerts to it via webhook. Avoid split-brain.
4. **MinIO single-node**: acceptable for local. **For prod, replace with S3 entirely** — don't run MinIO in-cluster unless you actually want distributed MinIO with ≥4 nodes.

## How to execute

After approving this plan:

```
/loop execute the LGTM plan from OBSERVABILITY-PLAN.md, one phase per iteration, commit and verify each phase before moving on, stop and report on any phase that fails verification
```

I'll do Phase 1 (MinIO) in the first iteration, schedule a wakeup, and continue through Phase 8. You can `/cancel-ralph` or interrupt at any iteration.
