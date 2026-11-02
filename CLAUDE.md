# repo-platform-gitops

Argo CD GitOps state for the platform. The cluster itself (kind, Argo CD bootstrap) lives in `repo-platform`.

The project's current opinions (what we do and why) live in `.claude/rules/`. Topic files load only when you touch matching paths. They are the source of truth, not a log. When a decision changes, edit the opinion in place in the same PR and delete what it supersedes; git history is the record. `README.md` is partly outdated.

## Layout (put config only where it belongs)
- `bootstrap/<env>.yaml`: root app per env; it renders `argocd-apps/` with the single input `env`.
- `argocd-apps/`: Helm chart for the app-of-apps.
  - `envs/<env>/cluster.yaml`: the env's cluster (env, server, prune, rawManifests) and its Kargo upstream.
  - `envs/<env>/apps/<app>.yaml`: one platform app in that env: chart, repoURL, version, namespace, wave
    (`enabled: false` disables). Kargo promotes by editing `version`; a human edits it only in the first stage.
  - `appsets/platform.yaml` is the platform ApplicationSet (plain Argo CD, Go template, matrix of two Git
    files generators); `templates/appset-platform.yaml` only substitutes the env.
  - `app-*.yaml` are the raw-manifest apps, rendered only when `cluster.yaml` has `rawManifests: true`.
  - `appset-apps.yaml` deploys app workloads from the separate app-gitops repo.
- `platform-apps/<app>/<env>/`: one upstream Helm chart per app.
  - `values.yaml`: chart values (the chart itself is declared in `argocd-apps/envs/<env>/apps/<app>.yaml`).
  - `grafana/<env>/dashboards/`: dashboards owned by Grafana Git Sync (UI edits arrive as PRs).
  - No raw manifests here.
- `manifests/<name>/<env>/`: raw manifests (CRs, ESO, CNPG, glue), each dir deployed by one `argocd-apps/templates/app-*.yaml` (check its `path:`).
- `network-policies/<env>/`: CiliumNetworkPolicies.
- `charts/<name>/`: Helm charts owned by this repo (e.g. `secrets-sync`), consumed by `app-*.yaml` apps via `path:` with per-env values under `manifests/<name>/<env>/values.yaml`. Each chart ships `examples/` that must render and validate.
