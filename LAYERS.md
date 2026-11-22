# Platform layers

The platform is read bottom-up. Each app's overrides live under `platform-apps/<layer>/<app>/<env>/`, and the
platform ApplicationSet turns the directory into the Application label `eve.io/layer`, so Argo CD and Grafana
can show one layer at a time. Layer 0 is installed by Terraform (`repo-platform/terraform-kind`): its entries
here stay `enabled: "false"` and only hold values for reference. Waves are the target per-layer sync order; each
`config.yaml` still carries its own `syncWave` until the ApplicationSet derives it from the layer.

| # | Layer | Target wave | Apps |
|---|---|---|---|
| 0 | `foundation` | -20 | cert-manager, cilium, metrics-server, prometheus-operator-crds |
| 1 | `data` | -15 | chromadb, cloudnative-pg, minio |
| 2 | `security` | -10 | authentik, external-secrets, openbao, vault-config-operator |
| 3 | `networking` | -5 | envoy-gateway, traefik |
| 4 | `delivery` | 0 | argo-rollouts, harbor, kargo |
| 5 | `observability` | 0 | alloy, grafana, kube-prometheus-stack, kube-state-metrics, loki, mimir, node-exporter, opentelemetry-operator, tempo |
| 6 | `addons` | 5 | headlamp, jellyfin, meshery, otel-demo |
| 7 | `tenants` | 10 | `charts/tenant` releases, then tenant apps |

Raw-manifest apps (`manifests/<name>/<env>/`) belong to layers too: cert-issuers, secret-stores, openbao-config,
authentik-config (security); gateway, gateway-crds, routes, cluster-dns, network-policies (networking); otel,
grafana-dashboards, grafana-db, config-drift (observability); progressive-delivery, argocd-repos (delivery);
demo-api, demo-db, tenancy (tenants); minio-init (data); priority-classes (foundation). Their templates get the
same label in a follow-up.

A tenant (`charts/tenant`) requires foundation, data and security and buys the layers above by tier.
