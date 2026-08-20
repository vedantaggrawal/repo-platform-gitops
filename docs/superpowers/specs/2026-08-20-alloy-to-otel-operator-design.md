# Design: Replace Alloy with the OpenTelemetry Operator (automatic observability)

Status: **proposed** — 2026-08-20
Scope: `local` env. Layout designed to promote to dev/stg/prod without restructuring.
Supersedes the collection layer of `OBSERVABILITY-PLAN.md` (Alloy → OTel). The LGTM
storage layer (Loki / Mimir / Tempo / MinIO / Grafana) is unchanged.

## Goal

Remove Grafana Alloy as the unified collector and stand up the OpenTelemetry
Operator in its place, such that:

1. Every telemetry pipeline Alloy runs today keeps working (no dashboard/alert regressions beyond the documented log-label change).
2. Application observability becomes **automatic**: annotate a workload and the
   operator injects the OTel SDK at admission — no code change, no per-app collector wiring.
3. Adding a service to the stack requires only opting into instrumentation
   (one annotation), which is the hook the future service-catalog/CMDB work will set.

## Decisions locked (from brainstorming)

- **Metrics: full OTel via Target Allocator.** The collector's Prometheus receiver
  plus the operator Target Allocator (`prometheusCR.enabled`) scrapes the existing
  `ServiceMonitor`/`PodMonitor` objects and the four cluster jobs. Alloy is fully
  replaced; kube-prometheus-stack Prometheus stays disabled.
- **Automatic scope: wire + demo.** Install the `Instrumentation` CR and annotate
  `devops-test-webserver` as a working example; every other workload is opt-in.
- **Spec first**, then implement into the existing GitOps ApplicationSet pattern.

## Current state — what Alloy does (must be preserved)

From `platform-apps/alloy/local/values.yaml`, one DaemonSet runs five pipelines:

| # | Alloy component | Destination |
|---|---|---|
| 1 | `prometheus.operator.servicemonitors` + `podmonitors` | Mimir (remote_write) |
| 2 | Manual `prometheus.scrape`: apiserver, kubelet, cadvisor, coredns | Mimir |
| 3 | `loki.source.kubernetes` (pod stdout tail) | Loki (`/loki/api/v1/push`) |
| 4 | `otelcol.receiver.otlp` :4317/:4318 → batch | Mimir / Loki / Tempo |
| 5 | `prometheus.remote_write` w/ `X-Scope-OrgID: anonymous` | Mimir |

Backends (unchanged), all in `monitoring` ns:
- Mimir push: `http://local-mimir-nginx.monitoring.svc.cluster.local/api/v1/push`
- Loki push (Alloy today): `http://local-loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push`
- Tempo OTLP: `local-tempo.monitoring.svc.cluster.local:4317`

Supporting: `manifests/alloy-rbac/local` grants node/endpoint discovery RBAC for pipeline 2.

## Target architecture

```
                          ┌─ opentelemetry-operator (Deployment) ─┐
                          │  • OpenTelemetryCollector CRD          │
   cert-manager ─webhook─▶│  • Instrumentation CRD (admission)     │
                          │  • Target Allocator provisioning       │
                          └────────────────────────────────────────┘
        injects SDK (annotation)         manages
                 │                          │
   ┌─────────────▼───────────┐   ┌──────────▼───────────────────────────────┐
   │ app pods (auto-instr.)  │   │ otel-agent  (DaemonSet, mode: daemonset)  │
   │  OTEL_EXPORTER_OTLP_* ──▶│──▶│  receivers: otlp(4317/4318), filelog      │
   └─────────────────────────┘   │  processors: k8sattributes, resource,batch│
                                 │  exporters: otlphttp/loki, otlp/tempo,    │
                                 │             prometheusremotewrite/mimir   │
                                 └──────────┬─────────────┬──────────────────┘
                                            │ logs        │ traces / OTLP metrics
                                            ▼             ▼
   ┌ otel-cluster (StatefulSet, mode: statefulset + Target Allocator) ┐   Loki  Tempo  Mimir
   │  receivers: prometheus (TA: SM/PM + 4 cluster scrape_configs)    │────────────────▶ Mimir
   │  exporters: prometheusremotewrite/mimir (X-Scope-OrgID)          │
   └──────────────────────────────────────────────────────────────────┘
```

Two collectors, split by concern (mirrors Alloy's "DaemonSet now, add Deployment in prod" note):

### A. `otel-agent` — DaemonSet (replaces Alloy pipelines 3 & 4)
- **mode:** `daemonset`; host-mounts `/var/log/pods` (read-only) for filelog.
- **receivers:**
  - `otlp` on `0.0.0.0:4317` (gRPC) and `0.0.0.0:4318` (HTTP) — same ports apps use today; the collector Service exposes them cluster-wide, and auto-instrumented pods target the node-local agent.
  - `filelog` with `include: /var/log/pods/*/*/*.log`, `operators: [{type: container}]` (auto-detects CRI/containerd/docker), `exclude` the collector's own logs.
- **processors:** `k8sattributes` (enrich with `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name`, `k8s.node.name`), `resource`, `batch`, `memory_limiter`.
- **exporters:**
  - Logs → `otlphttp/loki`: `endpoint: http://local-loki-gateway.monitoring.svc.cluster.local/otlp` (Loki 3.x native OTLP; posts to `/otlp/v1/logs`). Header `X-Scope-OrgID: anonymous`.
  - Traces → `otlp/tempo`: `endpoint: local-tempo.monitoring.svc.cluster.local:4317`, `tls.insecure: true`.
  - OTLP-metrics → `prometheusremotewrite/mimir`: `endpoint: http://local-mimir-nginx.monitoring.svc.cluster.local/api/v1/push`, `headers: {X-Scope-OrgID: anonymous}`.

### B. `otel-cluster` — StatefulSet + Target Allocator (replaces pipelines 1, 2, 5)
- **mode:** `statefulset` (required for TA scrape sharding), `replicas: 1` in `local`.
- **targetAllocator:** `enabled: true`, `prometheusCR: {enabled: true, serviceMonitorSelector: {}, podMonitorSelector: {}}` — discovers the same SM/PM objects Alloy watched (cilium, hubble, KSM, cert-manager, …).
- **receivers.prometheus.config.scrape_configs:** the four cluster jobs ported verbatim from Alloy (apiserver / kubelet / cadvisor `/metrics/cadvisor` / coredns), same relabel keep-rules, `bearer_token_file` + `insecure_skip_verify` TLS. TA aggregates these with the CR-derived jobs.
- **exporters:** `prometheusremotewrite/mimir` (same endpoint + `X-Scope-OrgID`).

> Deliberately **not** using `kubeletstats`/`hostmetrics` for node metrics — keeping the
> Prometheus scrape of kubelet+cadvisor preserves the exact metric names existing
> dashboards/alerts depend on. OTLP/SDK metrics still flow via the agent.

### C. `Instrumentation` CR — the "automatic" layer
- `opentelemetry.io/v1alpha1`, name `default`, namespace-scoped (installed in `devops-test-webserver` for the demo; documented for reuse elsewhere).
- `exporter.endpoint: http://<node-agent>:4318` (HTTP; SDKs default to http/proto). Endpoint resolves to the agent Service; for node-local delivery we set `OTEL_EXPORTER_OTLP_ENDPOINT` to the host IP via the operator's downward-API default.
- `propagators: [tracecontext, baggage, b3]`; `sampler: parentbased_traceidratio @ 1.0` in local.
- Opt-in per workload: `instrumentation.opentelemetry.io/inject-<lang>: "true"`.

## GitOps integration (existing ApplicationSet pattern)

New/changed files in `repo-platform-gitops`:

1. **`platform-apps/opentelemetry-operator/local/config.yaml` + `values.yaml`** — operator
   Helm chart (`open-telemetry/opentelemetry-operator`), ns `opentelemetry-operator`.
   - `config.yaml`: `enabled: "true"`, `chart: opentelemetry-operator`,
     `repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts`,
     `targetRevision: "0.9.*"` (pin at implementation), `namespace: opentelemetry-operator`,
     `syncWave: "-1"` (after cert-manager `-2`, before collectors).
   - `values.yaml`: `manager.collectorImage.repository: otel/opentelemetry-collector-k8s`
     (contrib-equivalent image that includes filelog/k8sattributes/prometheusremotewrite);
     JSON logs; leave admission webhooks on cert-manager (present).
2. **`manifests/otel/local/`** — the CRs the operator consumes, applied by a dedicated
   Application (mirrors `app-argocd-repos` / `app-minio-init`):
   - `collector-agent.yaml` (`OpenTelemetryCollector`, daemonset)
   - `collector-cluster.yaml` (`OpenTelemetryCollector`, statefulset + TA)
   - `instrumentation.yaml` (`Instrumentation`)
   - `rbac.yaml` — ClusterRole/Binding for TA (`servicemonitors`,`podmonitors`,`namespaces`
     get/list/watch) and for the cluster collector's Prometheus discovery
     (`nodes`,`nodes/metrics`,`endpoints`,`pods`,`services` + `nodes/proxy`), replacing
     `manifests/alloy-rbac`.
3. **`argocd-apps/templates/app-otel.yaml`** — Application pointing at `manifests/otel/{env}`,
   `argocd.argoproj.io/sync-wave: "2"` (after the operator app so CRDs + webhook exist),
   `ServerSideApply=true`, destination ns `opentelemetry-operator`.
4. **Disable Alloy:** `platform-apps/alloy/local/config.yaml` → `enabled: "false"`; retire
   `app-alloy-rbac.yaml` + `manifests/alloy-rbac` (RBAC superseded by `manifests/otel/local/rbac.yaml`).
5. **Demo annotation:** add `instrumentation.opentelemetry.io/inject-<lang>: "true"` to the
   `devops-test-webserver` pod template (in `repo-app-gitops`, its owning repo) — flagged as a
   follow-up commit in that repo, not this one.

### Ordering / sync waves
`cert-manager (-2)` → `opentelemetry-operator (-1)` → operator Deployment + webhook Healthy →
`app-otel (2)` applies CRs. Argo retry (limit 3, backoff) absorbs the window where the
webhook is briefly not-ready. Alloy is disabled in the same change; there is a short overlap
where both may run — acceptable (double-writes are idempotent to Mimir/Loki/Tempo).

## Trade-offs & risks

- **Log label shape changes.** Alloy's `loki.source.kubernetes` set Loki index labels
  `namespace/pod/container/node`. The OTel path sends OTLP; Loki maps resource attributes to
  **structured metadata**, and only a small set become stream labels. LogQL like
  `{namespace="x"}` may need to become `{service_name="x"} | k8s_namespace_name="x"` or Loki
  `otlp_config` label hints. **Mitigation:** set Loki `limits_config.otlp_config` to promote
  `k8s.namespace.name`,`k8s.pod.name`,`k8s.container.name` to stream labels, preserving current queries.
- **`loki` exporter is removed** from current collector builds — using `otlphttp` to Loki's
  native endpoint is the only supported path (already assumed above).
- **Target Allocator is another moving part** (extra StatefulSet + RBAC). Failure mode is
  "metrics stop"; agent-collected logs/traces are unaffected.
- **Collector image must include contrib components** (filelog, k8sattributes,
  prometheusremotewrite). The stock `otel/opentelemetry-collector` core image does not —
  hence `otel/opentelemetry-collector-k8s`.
- **Metrics remote_write dedup:** during the Alloy/OTel overlap, identical series double-write;
  Mimir dedups on identical labels+timestamp, so no corruption, but disable Alloy promptly.

## Verification plan

1. Operator Deployment Ready; `OpenTelemetryCollector`/`Instrumentation` CRDs present.
2. `otel-agent` DaemonSet on both nodes; `otel-cluster` StatefulSet + TA pods Ready.
3. Mimir has fresh samples for `apiserver`, `kubelet`, `cadvisor`, `coredns` jobs and for a
   chart ServiceMonitor target (e.g. cert-manager) — query Grafana Explore/Mimir.
4. Loki shows pod logs with promoted `k8s_namespace_name` label; a known LogQL query returns rows.
5. Annotate `devops-test-webserver`; confirm the operator injected an init container + OTEL env,
   and Tempo shows a trace for a request to it (TraceQL by `service.name`).
6. Alloy Deployment/DaemonSet gone; no scrape/log gaps in Grafana across the cutover.

## Rollback

Revert the commit: `platform-apps/alloy/local/config.yaml enabled:"true"` restores Alloy;
set `opentelemetry-operator` + `app-otel` `enabled/prune` so Argo removes the operator and CRs.
Because storage (LGTM) is untouched, rollback is collection-layer only.

## Out of scope

- Multi-env promotion (dev/stg/prod values) — same layout, added when those envs adopt it.
- Multi-tenant `X-Scope-OrgID` beyond `anonymous`.
- Auto-instrumenting workloads other than the demo (opt-in later, likely via the service catalog).
- The broader CMDB/service-catalog control plane (separate design).
