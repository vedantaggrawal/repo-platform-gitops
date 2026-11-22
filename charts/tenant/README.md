# tenant

A tenant's whole landscape from one values file. Onboarding a tenant is adding `tenants/<name>/tenant.yaml`
(see `examples/demo.yaml`); nothing tenant-specific is written anywhere else.

| Renders | From |
|---|---|
| Namespace `tenant-<name>-<workload>` per workload, labelled `eve.io/tenant`, Pod Security restricted | `name`, `workloads`, `namespaceLabels` |
| ResourceQuota `<tier>-tier`, LimitRange `defaults` | `tier` → `tiers.<tier>` (platform defaults in `values.yaml`) |
| NetworkPolicies `default-deny`, `allow-baseline` (same namespace, ingress from gateway namespaces, DNS egress) | `network` |
| RoleBindings to the shared ClusterRoles `tenant-{admin,developer,viewer}` for Group `oidc:tenant-<name>-<role>` | `roles`, `kubernetes.groupPrefix` |
| Argo CD AppProject `tenant-<name>`: destinations `tenant-<name>-*` (+ extras), source repos, blacklist of platform-owned kinds, roles admin/dev/viewer bound to the Authentik groups | `argocd` |
| ConfigMap `authentik-blueprint-tenant-<name>`: tenant group with `tenant_id`/`tier`, role groups, self-service admin role, API provider `eve-<name>-api` (public, PKCE, 10-minute tokens with `tenant_id`) | `authentik` |

## Per-tenant file

```yaml
name: acme
tier: free
workloads: [app]
argocd:
  sourceRepos: [https://github.com/org/acme-gitops.git]
```
Everything else is a platform default. A new tier is a new key under `tiers`; a new gateway namespace is one
entry in `network.ingressFromNamespaces`.

## Wiring (done by the next PR, not by this chart)

- One plain ApplicationSet over `tenants/*/tenant.yaml` renders this chart once per tenant.
- The Authentik chart lists the ConfigMap in `blueprints.configMaps`.
- Group names: Kubernetes RoleBindings use `oidc:tenant-<name>-developer`, Authentik and Argo CD use
  `tenant-<name>-dev`. Reproduced as found; align them when wiring (`roles.developer.kubernetesGroup`).

## Not in this chart yet

OpenBao policy and auth role for `secret/tenants/<name>/*`, Grafana org and datasources, observability
tenant limits, Harbor project, S3 identity. Each is a later slice with its own values block.
