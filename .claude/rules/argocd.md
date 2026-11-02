---
paths:
  - "argocd-apps/**"
  - "bootstrap/**"
  - "manifests/**"
  - "argocd-apps/envs/**"
---
# Argo CD

- **One root app per env.** `bootstrap/<env>.yaml` sets only `env` on the `argocd-apps` chart; the cluster server, prune and raw-manifest flag come from `argocd-apps/envs/<env>/cluster.yaml`. A new env is a bootstrap file plus `envs/<env>/{cluster,apps}.yaml` and `platform-apps/*/<env>/values.yaml`.
  - *Not* a `clusters/*.yaml` matrix: routing belongs in git.
  - *Not* Kustomize overlays: they need a patch per app per overlay.
- **App workloads are multi-source:** `repo-helm-chart`, plus `$values` from `repo-app-gitops` at `apps/*/<env>`. A new app is a new directory, with no AppSet edit.
- **prod runs with `prune: false`.** *Why:* a deleted file must not delete prod workloads.
- **Disable, don't delete:** set `enabled: false` on the app's entry in `argocd-apps/envs/<env>/apps.yaml`, with a comment saying why.
- **Argo CD 2.10: ESO, ESO-generator and CNPG CRs never go in a ServerSideApply app.**
  - The platform AppSet forces SSA (client-side apply overflows the last-applied annotation on large CRDs), and these CRs make the diff panic.
  - Put them in a `manifests/` app without `ServerSideApply=true`, e.g. `app-authentik-config`, `app-minio-init`, `app-secret-stores`.
- **OCI Helm repos** are registered with `enableOCI: "true"` in `manifests/argocd-repos/`. 2.10 doesn't detect bare OCI URLs.
- **Don't rely on cross-app sync waves.** Make dependents tolerate a missing dependency (`SkipDryRunOnMissingResource`, optional mounts, retries).
- **Stateful or bootstrap resources** (CNPG clusters, CoreDNS) carry `argocd.argoproj.io/sync-options: Delete=false,Prune=false`.
- **Add only when needed:** per-team AppProjects, PR preview envs, per-project AppSets.
