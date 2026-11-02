# repo-platform-gitops

Argo CD GitOps state for the platform. The cluster itself (kind, Argo CD bootstrap) lives in `repo-platform`.

The project's current opinions (what we do and why) live in `.claude/rules/`. Topic files load only when you touch matching paths. They are the source of truth, not a log. When a decision changes, edit the opinion in place in the same PR and delete what it supersedes; git history is the record. `README.md` is partly outdated.

## Layout (put config only where it belongs)
- `bootstrap/<env>.yaml`: root app per env; it renders `argocd-apps/` with the single input `env`.
- `argocd-apps/`: Helm chart for the app-of-apps.
  - `envs/<env>/cluster.yaml`: the env's cluster (env, server, prune, active, controlPlane, rawManifests) and its
    Kargo upstream.
  - `envs/<env>/apps.yaml`: the stage's catalogue, every platform app in one file (`apps.<name>`: chart, repoURL,
    version, namespace, wave, enabled). Promotion is a stage snapshot: Kargo copies `local`'s apps.yaml, values
    files and config directories into the next stage verbatim. Humans edit them only in `local`.
  - `app-appsets.yaml` applies `argocd/appsets/` on the control plane (`cluster.yaml: controlPlane`); the last
    Helm-rendered Application, gone when the root app points at `argocd/` directly.
  - `appset-apps.yaml` deploys app workloads from the separate app-gitops repo.
- `platform-apps/<app>/<env>/`: one upstream Helm chart per app.
  - `values.yaml`: chart values; `local`'s file is the source, later stages receive it with the snapshot.
  - `grafana/<env>/dashboards/`: dashboards owned by Grafana Git Sync (UI edits arrive as PRs).
  - No raw manifests here.
- `argocd/appsets/`: the ApplicationSets, plain Argo CD manifests (Go template, native generators), never rendered
  by Helm. `platform.yaml` fans out each stage's `apps.yaml`; `manifests.yaml` makes one Application per
  `stages/<stage>/manifests/<name>/`.
- `stages/<stage>/manifests/<name>/`: raw manifests (CRs, ESO, CNPG, glue, network policies) plus `app.yaml` with
  the Application's settings (namespace, wave; optional project, syncOptions, retry, ignoreDifferences,
  extraSources). Adding a directory adds an Application; no template to write. Promotion copies the
  stage's directories forward.
- `charts/<name>/`: Helm charts owned by this repo (e.g. `secrets-sync`), consumed from a `stages/<stage>/manifests/<name>/` directory via `path:` with that stage's values. Each chart ships `examples/` that must render and validate.
