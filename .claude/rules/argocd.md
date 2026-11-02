---
paths:
  - "argocd-apps/**"
  - "bootstrap/**"
  - "stages/**"
  - "argocd/**"
  - "argocd-apps/envs/**"
---
# Argo CD

- **One root app per env.** `bootstrap/<env>.yaml` sets only `env` on the `argocd-apps` chart; the cluster server, prune and raw-manifest flag come from `argocd-apps/envs/<env>/cluster.yaml`. A new env is `envs/<env>/{cluster,apps}.yaml` (`active: true` once the cluster exists), a bootstrap file and `platform-apps/*/<env>/values.yaml`.
  - Routing lives in git: `envs/<env>/cluster.yaml` says where an env runs and the platform ApplicationSet reads it; no cluster Secret labels, no env substitution.
  - *Not* Kustomize overlays: they need a patch per app per overlay.
- **App workloads are multi-source:** `repo-helm-chart`, plus `$values` from `repo-app-gitops` at `apps/*/<env>`. A new app is a new directory, with no AppSet edit.
- **prod runs with `prune: false`.** *Why:* a deleted file must not delete prod workloads.
- **Disable, don't delete:** set `enabled: false` on the app's entry in `argocd-apps/envs/<env>/apps.yaml`, with a comment saying why.
- **ApplicationSets are plain Argo CD manifests** (`argocd/appsets/`, Go template, native generators), applied as they are on the control plane; the Helm chart never renders them. A raw-manifest directory gets an Application from `app.yaml`, never from a hand-written template. *Why:* two template languages in one file are unreadable and unlintable.
- **Promotion is a stage snapshot.** Kargo's freight is a commit of `local`'s state (apps.yaml versions, values files, config directories); a promotion copies them verbatim into the next stage. Per-chart warehouses bump versions in `local` only. Humans edit `local`; later stages are written by promotion. *Why:* one unit per stage: an old chart can never meet newer config, and a checkpoint is one commit.
- **Argo CD 2.10: ESO, ESO-generator and CNPG CRs never go in a ServerSideApply app.**
  - The platform AppSet forces SSA (client-side apply overflows the last-applied annotation on large CRDs), and these CRs make the diff panic.
  - Put them in a `stages/<stage>/manifests/<name>/` directory whose `app.yaml` has no `ServerSideApply=true`, e.g. `authentik-config`, `minio-init`, `secret-stores`.
- **OCI Helm repos** are registered with `enableOCI: "true"` in `stages/<stage>/manifests/argocd-repos/`. 2.10 doesn't detect bare OCI URLs.
- **Don't rely on cross-app sync waves.** Make dependents tolerate a missing dependency (`SkipDryRunOnMissingResource`, optional mounts, retries).
- **Stateful or bootstrap resources** (CNPG clusters, CoreDNS) carry `argocd.argoproj.io/sync-options: Delete=false,Prune=false`.
- **Add only when needed:** per-team AppProjects, PR preview envs, per-project AppSets.
