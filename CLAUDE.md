# repo-platform-gitops

Argo CD GitOps state for the platform. The cluster itself (kind, Argo CD bootstrap) lives in `repo-platform`.

The project's current opinions (what we do and why) live in `.claude/rules/`. Topic files load only when you touch matching paths. They are the source of truth, not a log. When a decision changes, edit the opinion in place in the same PR and delete what it supersedes; git history is the record. `README.md` is partly outdated.

## Layout (put config only where it belongs)
- `bootstrap/<env>.yaml`: root app per env; it renders `argocd-apps/`.
- `argocd-apps/`: Helm chart for the app-of-apps.
  - `appset-platform.yaml` turns every `platform-apps/<app>/<env>/` into an app.
  - `app-*.yaml` are the raw-manifest apps, rendered only for `rawManifestEnvs`.
  - `appset-apps.yaml` deploys app workloads from the separate app-gitops repo.
- `platform-apps/<app>/<env>/`: one upstream Helm chart per app.
  - `config.yaml`: chart, repoURL, targetRevision, namespace, syncWave, enabled.
  - `values.yaml`: chart values.
  - No raw manifests here.
- `manifests/<name>/<env>/`: raw manifests (CRs, ESO, CNPG, glue), each dir deployed by one `argocd-apps/templates/app-*.yaml` (check its `path:`).
- `network-policies/<env>/`: CiliumNetworkPolicies.
