---
paths:
  - "argocd-apps/**"
  - "bootstrap/**"
  - "manifests/**"
---
# Argo CD

- **Argo CD 2.10: ESO, ESO-generator and CNPG CRs never go in a ServerSideApply app.**
  - The platform ApplicationSet forces SSA, and these CRs make the diff panic.
  - Put them in a `manifests/` app without `ServerSideApply=true`, e.g. `app-authentik-config`, `app-minio-init`, `app-secret-stores`. Some `app-*.yaml` do use SSA.
- **Don't rely on cross-app sync waves.**
  - Observed: the root app's waves did not hold ApplicationSet children back.
  - Make dependents tolerate a missing dependency (`SkipDryRunOnMissingResource`, optional mounts, retries).
- **Stateful or bootstrap resources** (CNPG clusters, CoreDNS) carry `argocd.argoproj.io/sync-options: Delete=false,Prune=false`.
