---
paths:
  - "argocd-apps/**"
  - "bootstrap/**"
  - "manifests/**"
  - "platform-apps/*/*/config.yaml"
---
# Argo CD

- **One root app per env.** `bootstrap/<env>.yaml` sets `env`, `cluster` and `prune` on the `argocd-apps` chart. A new env is a bootstrap file plus `<env>/` dirs.
  - *Not* a `clusters/*.yaml` matrix: routing belongs in git.
  - *Not* Kustomize overlays: they need a patch per app per overlay.
- **App workloads are multi-source:** `repo-helm-chart`, plus `$values` from `repo-app-gitops` at `apps/*/<env>`. A new app is a new directory, with no AppSet edit.
- **prod runs with `prune: false`.** *Why:* a deleted file must not delete prod workloads.
- **Disable, don't delete:** set `enabled: "false"` in `config.yaml`, with a comment saying why.
- **Argo CD 2.10: ESO, ESO-generator and CNPG CRs never go in a ServerSideApply app.**
  - The platform AppSet forces SSA (client-side apply overflows the last-applied annotation on large CRDs), and these CRs make the diff panic.
  - Put them in a `manifests/` app without `ServerSideApply=true`, e.g. `app-authentik-config`, `app-minio-init`, `app-secret-stores`.
- **OCI Helm repos** are registered with `enableOCI: "true"` in `manifests/argocd-repos/`. 2.10 doesn't detect bare OCI URLs.
- **Don't rely on cross-app sync waves.** Make dependents tolerate a missing dependency (`SkipDryRunOnMissingResource`, optional mounts, retries).
- **Stateful or bootstrap resources** (CNPG clusters, CoreDNS) carry `argocd.argoproj.io/sync-options: Delete=false,Prune=false`.
- **Add only when needed:** per-team AppProjects, PR preview envs, per-project AppSets.
