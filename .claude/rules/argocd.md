---
paths:
  - "argocd-apps/**"
  - "bootstrap/**"
  - "manifests/**"
  - "argocd-apps/apps/**"
  - "argocd-apps/appsets/**"
  - "argocd-apps/envs/**"
---
# Argo CD

- **One root app per env.** `bootstrap/<env>.yaml` sets only `env` on the `argocd-apps` chart; the cluster server, prune and raw-manifest flag come from `argocd-apps/envs/<env>/cluster.yaml`. A new env is a bootstrap file, `envs/<env>/cluster.yaml`, a labelled cluster Secret, a `versions.<env>` line per app and `platform-apps/*/<env>/values.yaml`.
  - Clusters are declared in git as Argo CD cluster Secrets (`manifests/argocd-clusters/<env>/`) with labels `env` and `prune`; ApplicationSets route on them (cluster generator) with no env substitution.
  - *Not* Kustomize overlays: they need a patch per app per overlay.
- **App workloads are multi-source:** `repo-helm-chart`, plus `$values` from `repo-app-gitops` at `apps/*/<env>`. A new app is a new directory, with no AppSet edit.
- **prod runs with `prune: false`.** *Why:* a deleted file must not delete prod workloads.
- **Disable, don't delete:** comment the env's line out under `versions:` in `argocd-apps/apps/<app>.yaml`, with a comment saying why.
- **ApplicationSets are plain Argo CD manifests** (`argocd-apps/appsets/`, Go template, native generators), included verbatim by the control-plane root app. *Why:* two template languages in one file are unreadable and unlintable.
- **Declare each app once.** Chart, repo, namespace and wave live in one file per app; only the version is per env. *Why:* per-env copies drift and hide what actually differs between stages.
- **Argo CD 2.10: ESO, ESO-generator and CNPG CRs never go in a ServerSideApply app.**
  - The platform AppSet forces SSA (client-side apply overflows the last-applied annotation on large CRDs), and these CRs make the diff panic.
  - Put them in a `manifests/` app without `ServerSideApply=true`, e.g. `app-authentik-config`, `app-minio-init`, `app-secret-stores`.
- **OCI Helm repos** are registered with `enableOCI: "true"` in `manifests/argocd-repos/`. 2.10 doesn't detect bare OCI URLs.
- **Don't rely on cross-app sync waves.** Make dependents tolerate a missing dependency (`SkipDryRunOnMissingResource`, optional mounts, retries).
- **Stateful or bootstrap resources** (CNPG clusters, CoreDNS) carry `argocd.argoproj.io/sync-options: Delete=false,Prune=false`.
- **Add only when needed:** per-team AppProjects, PR preview envs, per-project AppSets.
