# repo-platform-gitops

Argo CD GitOps state for the platform. The cluster itself (kind, Argo CD bootstrap) lives in `repo-platform`.

The project's current opinions (what we do and why) live in `.claude/rules/`. Topic files load only when you touch matching paths. They are the source of truth, not a log. When a decision changes, edit the opinion in place in the same PR and delete what it supersedes; git history is the record. `README.md` is partly outdated.

## Layout (put config only where it belongs)
- `bootstrap/<env>.yaml`: root app per env; it renders `argocd-apps/` with the single input `env`.
- `argocd-apps/`: Helm chart for the app-of-apps, shrinking: it still renders the AppProjects, the workload and
  kargo-demo ApplicationSets and `app-appsets.yaml` (applies `argocd/appsets/`), and holds `envs/<env>/cluster.yaml`
  (server, prune, active, controlPlane, rawManifests, Kargo upstream) until the root app points at `argocd/` directly.
- `stages/<stage>/`: everything a stage runs. `apps.yaml` is the catalogue (`apps.<name>`: chart, repoURL, version,
  namespace, wave, enabled; optional skipCrds, retry, ignoreDifferences); `values/<app>.yaml` the chart values;
  `manifests/<name>/` the raw manifests with their `app.yaml`. Promotion is a stage snapshot: Kargo copies `local`'s
  catalogue, values and manifests into the next stage verbatim; humans edit them only in `local`.
- `argocd/appsets/`: the ApplicationSets, plain Argo CD manifests (Go template, native generators), never rendered
  by Helm. `platform.yaml` fans out each stage's `apps.yaml`; `manifests.yaml` makes one Application per
  `stages/<stage>/manifests/<name>/`.
- `stages/<stage>/manifests/<name>/`: raw manifests (CRs, ESO, CNPG, glue, network policies) plus `app.yaml` with
  the Application's settings (namespace, wave; optional project, syncOptions, retry, ignoreDifferences,
  extraSources). Adding a directory adds an Application; no template to write. Promotion copies the
  stage's directories forward.
- `charts/<name>/`: Helm charts owned by this repo (e.g. `secrets-sync`), consumed from a `stages/<stage>/manifests/<name>/` directory via `path:` with that stage's values. Each chart ships `examples/` that must render and validate.
